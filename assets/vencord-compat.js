/**
 * Vencord & Vendetta / Bunny Compatibility Layer for Unbound (iOS)
 * Exposes window.Vencord, window.vencord, window.vendetta, window.bunny
 */
(function (global) {
    if (global.__vencordCompatInitialized) return;
    global.__vencordCompatInitialized = true;

    // Helper: Metro / Webpack Module Lookup
    function getMetro() {
        return global.unbound?.metro || {
            find(filter) {
                const map = global.modules ?? global.__c?.();
                if (!map) return null;
                for (const m of (map.values ? map.values() : Object.values(map))) {
                    const e = m?.publicModule?.exports ?? m?.exports ?? m;
                    if (!e) continue;
                    try { if (filter(e)) return e; } catch (_) {}
                    if (e.default && filter(e.default)) return e.default;
                }
                return null;
            },
            findByProps(...props) {
                return this.find(m => props.every(p => m && typeof m === 'object' && p in m));
            },
            findByCode(...snippets) {
                const map = global.modules ?? global.__c?.();
                if (!map) return null;
                for (const m of (map.values ? map.values() : Object.values(map))) {
                    const src = m?.factory?.toString?.() || m?.toString?.() || '';
                    if (snippets.every(s => src.includes(s))) {
                        return m?.publicModule?.exports ?? m?.exports ?? m;
                    }
                }
                return null;
            },
            findStore(name) {
                return this.find(m => m?._dispatcher && (m.getName?.() === name || m.displayName === name));
            }
        };
    }

    // Storage backing
    const pluginStorage = {};

    // Patcher Implementation
    const patches = new Map();

    function createPatcher() {
        function patch(type, caller, parent, prop, hook) {
            if (!parent || typeof parent[prop] !== 'function') {
                return () => {};
            }
            const orig = parent[prop];
            const unpatch = () => {
                parent[prop] = orig;
            };

            if (!patches.has(caller)) {
                patches.set(caller, []);
            }
            patches.get(caller).push(unpatch);

            if (type === 'before') {
                parent[prop] = function (...args) {
                    try {
                        const result = hook.call(this, args);
                        if (Array.isArray(result)) args = result;
                    } catch (e) {
                        console.error(`[Vencord Patcher] Error in before patch (${caller}):`, e);
                    }
                    return orig.apply(this, args);
                };
            } else if (type === 'after') {
                parent[prop] = function (...args) {
                    const res = orig.apply(this, args);
                    try {
                        const hookRes = hook.call(this, args, res);
                        return hookRes !== undefined ? hookRes : res;
                    } catch (e) {
                        console.error(`[Vencord Patcher] Error in after patch (${caller}):`, e);
                        return res;
                    }
                };
            } else if (type === 'instead') {
                parent[prop] = function (...args) {
                    try {
                        return hook.call(this, args, orig.bind(this));
                    } catch (e) {
                        console.error(`[Vencord Patcher] Error in instead patch (${caller}):`, e);
                        return orig.apply(this, args);
                    }
                };
            }
            return unpatch;
        }

        return {
            before: (caller, parent, prop, hook) => patch('before', caller, parent, prop, hook),
            after: (caller, parent, prop, hook) => patch('after', caller, parent, prop, hook),
            instead: (caller, parent, prop, hook) => patch('instead', caller, parent, prop, hook),
            unpatchAll: (caller) => {
                const list = patches.get(caller);
                if (list) {
                    list.forEach(u => { try { u(); } catch (_) {} });
                    patches.delete(caller);
                }
            }
        };
    }

    const patcher = createPatcher();

    // Vencord Plugins Manager
    const registeredPlugins = {};
    const startedPlugins = new Set();

    function registerPlugin(def) {
        if (!def || !def.name) return;
        registeredPlugins[def.name] = def;
        if (def.enabled !== false && typeof def.start === 'function') {
            try {
                def.start();
                startedPlugins.add(def.name);
                console.log(`[Vencord] Started plugin: ${def.name}`);
            } catch (e) {
                console.error(`[Vencord] Failed to start plugin ${def.name}:`, e);
            }
        }
    }

    function definePlugin(def) {
        registerPlugin(def);
        return def;
    }

    // Built-in Vencord Utilities
    const Util = {
        findInReactTree(tree, filter) {
            if (!tree) return null;
            if (filter(tree)) return tree;
            if (Array.isArray(tree)) {
                for (const item of tree) {
                    const found = Util.findInReactTree(item, filter);
                    if (found) return found;
                }
            } else if (typeof tree === 'object') {
                const props = tree.props || tree.children;
                if (props) {
                    const found = Util.findInReactTree(props, filter);
                    if (found) return found;
                }
            }
            return null;
        },
        escapeRegex: (str) => str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'),
        showToast(message, options = {}) {
            if (global.unbound?.toasts?.show) {
                global.unbound.toasts.show(message, options);
            } else if (global.UnboundNative?.notifications?.show) {
                global.UnboundNative.notifications.show("Unbound", message, 1, false, null);
            } else {
                console.log("[Toast]", message);
            }
        }
    };

    // Construct Vencord object
    const VencordObj = {
        Plugins: {
            plugins: registeredPlugins,
            registerPlugin,
            definePlugin,
            isStarted: (name) => startedPlugins.has(name),
            startPlugin: (name) => {
                const p = registeredPlugins[name];
                if (p && typeof p.start === 'function') {
                    p.start();
                    startedPlugins.add(name);
                }
            },
            stopPlugin: (name) => {
                const p = registeredPlugins[name];
                if (p && typeof p.stop === 'function') {
                    p.stop();
                    startedPlugins.delete(name);
                    patcher.unpatchAll(name);
                }
            }
        },
        Webpack: {
            get findByProps() { return getMetro().findByProps.bind(getMetro()); },
            get find() { return getMetro().find.bind(getMetro()); },
            get findByCode() { return getMetro().findByCode.bind(getMetro()); },
            get findStore() { return getMetro().findStore.bind(getMetro()); },
            get Common() {
                const metro = getMetro();
                return {
                    React: metro.findByProps('createElement', 'useState'),
                    Flux: metro.findByProps('Store', 'connectStores'),
                    FluxDispatcher: metro.findByProps('_dispatch', 'dispatch'),
                    constants: metro.findByProps('Endpoints', 'UserFlags'),
                    channels: metro.findStore('ChannelStore'),
                    guilds: metro.findStore('GuildStore'),
                    messages: metro.findStore('MessageStore'),
                    users: metro.findStore('UserStore'),
                    toasts: metro.findByProps('showToast', 'createToast')
                };
            }
        },
        Patcher: patcher,
        Util: Util,
        Api: {
            Commands: {
                registerCommand: (cmd) => console.log("[Vencord Commands] registered", cmd?.name),
                unregisterCommand: (name) => console.log("[Vencord Commands] unregistered", name)
            },
            MessageEvents: {
                _listeners: [],
                addPreSendListener(fn) { this._listeners.push(fn); }
            }
        },
        Settings: {
            plugins: new Proxy(pluginStorage, {
                get(target, prop) {
                    return target[prop] || (global.unbound?.storage?.get?.(prop) ?? {});
                },
                set(target, prop, value) {
                    target[prop] = value;
                    global.unbound?.storage?.set?.(prop, value);
                    return true;
                }
            })
        },
        definePlugin: definePlugin
    };

    // Vendetta / Bunny Compatibility Object
    const VendettaObj = {
        metro: {
            get findByProps() { return getMetro().findByProps.bind(getMetro()); },
            get find() { return getMetro().find.bind(getMetro()); },
            get findByTypeName() { return getMetro().find.bind(getMetro()); },
            get findStore() { return getMetro().findStore.bind(getMetro()); },
            get common() { return VencordObj.Webpack.Common; }
        },
        patcher: patcher,
        storage: {
            createProxy: (target = {}) => new Proxy(target, {
                get: (t, p) => t[p],
                set: (t, p, v) => { t[p] = v; return true; }
            }),
            useProxy: (s) => s
        },
        ui: {
            toasts: { showToast: Util.showToast },
            alerts: { showConfirmationAlert: (opts) => alert(opts?.title || opts?.content) }
        },
        plugin: {
            id: 'unbound-compat',
            manifest: { name: 'Unbound Compat', version: '2.5.1' }
        }
    };

    // Bind Globals
    global.Vencord = VencordObj;
    global.vencord = VencordObj;
    global.vendetta = VendettaObj;
    global.bunny = VendettaObj;

    // -------------------------------------------------------------
    // Built-in Vencord Power Features
    // -------------------------------------------------------------

    // 1. FakeNitro / Free Emoji Bypass
    function initFakeNitro() {
        const ready = () => {
            const metro = getMetro();
            const messageModule = metro.findByProps('sendMessage', 'editMessage');
            if (!messageModule || !messageModule.sendMessage) return;

            patcher.before('VencordFakeNitro', messageModule, 'sendMessage', ([channelId, msg, ...rest]) => {
                if (!msg || !msg.content) return;
                // Convert <:name:id> or <a:name:id> custom emojis to direct CDN links if user doesn't have Nitro
                const emojiRegex = /<(a?):([a-zA-Z0-9_]+):([0-9]+)>/g;
                msg.content = msg.content.replace(emojiRegex, (match, animated, name, id) => {
                    const ext = animated ? 'gif' : 'png';
                    return `https://cdn.discordapp.com/emojis/${id}.${ext}?size=64&quality=lossless`;
                });
                return [channelId, msg, ...rest];
            });
            console.log('[Vencord] FakeNitro / Emoji Bypass active');
        };

        if (global.unbound?.ready) ready();
        else setTimeout(ready, 2000);
    }

    // 2. Clean URLs (Strip tracking parameters like utm_*, si=, etc.)
    function initCleanURLs() {
        const trackers = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content', 'si', 'igshid', 'fbclid'];
        const stripTrackers = (urlStr) => {
            try {
                const url = new URL(urlStr);
                let changed = false;
                for (const t of trackers) {
                    if (url.searchParams.has(t)) {
                        url.searchParams.delete(t);
                        changed = true;
                    }
                }
                return changed ? url.toString() : urlStr;
            } catch (_) {
                return urlStr;
            }
        };

        const ready = () => {
            const metro = getMetro();
            const messageModule = metro.findByProps('sendMessage');
            if (!messageModule) return;

            patcher.before('VencordCleanURLs', messageModule, 'sendMessage', ([channelId, msg, ...rest]) => {
                if (!msg || !msg.content) return;
                const urlRegex = /https?:\/\/[^\s]+/g;
                msg.content = msg.content.replace(urlRegex, (u) => stripTrackers(u));
                return [channelId, msg, ...rest];
            });
            console.log('[Vencord] Clean URLs active');
        };

        if (global.unbound?.ready) ready();
        else setTimeout(ready, 2000);
    }

    initFakeNitro();
    initCleanURLs();

    console.log('[Vencord] Compatibility Layer successfully mounted.');
})(globalThis);
