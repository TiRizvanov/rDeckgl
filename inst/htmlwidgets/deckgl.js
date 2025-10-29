// deckgl.js - Deck.gl htmlwidget for R

// Helper function to decode base64 to Uint8Array
function base64ToUint8Array(base64) {
  try {
    const binary_string = atob(base64);
    const len = binary_string.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
      bytes[i] = binary_string.charCodeAt(i);
    }
    return bytes;
  } catch (e) {
    console.error("[deckgl] Failed to decode base64 string:", base64.substring(0, 100) + "...", e);
    throw e;
  }
}

const deckGlModule = { promise: null };

async function ensureDeckGlModules() {
  if (!deckGlModule.promise) {
    deckGlModule.promise = (async () => {
      const deck = window.deck;
      if (!deck || !deck.Deck) {
        throw new Error('Deck.gl libraries are not loaded. Ensure deckgl-bundle dependency is registered.');
      }

      const JSONConverter = deck.JSONConverter || (window.deck__json && window.deck__json.JSONConverter);
      const JSONConfiguration = deck.JSONConfiguration || (window.deck__json && window.deck__json.JSONConfiguration);

      if (!JSONConverter || !JSONConfiguration) {
        throw new Error('Deck.gl JSONConverter is unavailable. Ensure @deck.gl/json is accessible via deckgl-bundle.');
      }

      const loadersGlobal = window.loaders;
      const csvLoader = window.CSVLoader || (loadersGlobal && loadersGlobal.CSVLoader);
      if (loadersGlobal && typeof loadersGlobal.registerLoaders === 'function' && csvLoader) {
        try {
          loadersGlobal.registerLoaders(csvLoader);
        } catch (err) {
          console.warn('[deckgl] Failed to register CSVLoader:', err);
        }
      }

      return { deck, JSONConverter, JSONConfiguration };
    })();
  }
  return deckGlModule.promise;
}

function collectDeckGlTokens(spec) {
  const classNames = new Set();
  const enumNames = new Set();

  const walk = (node) => {
    if (node === null || node === undefined) return;
    if (Array.isArray(node)) {
      node.forEach(walk);
      return;
    }
    if (typeof node === 'object') {
      if (typeof node['@@type'] === 'string') {
        classNames.add(node['@@type']);
      }
      Object.keys(node).forEach((key) => walk(node[key]));
      return;
    }
    if (typeof node === 'string' && node.startsWith('@@#')) {
      const enumToken = node.slice(3);
      const enumName = enumToken.split('.')[0];
      if (enumName) enumNames.add(enumName);
    }
  };

  walk(spec);
  return {
    classNames: Array.from(classNames),
    enumNames: Array.from(enumNames)
  };
}

function resolveDeckExport(deck, name) {
  if (!deck || typeof name !== 'string') return null;
  if (deck[name]) return deck[name];
  if (name === 'DeckGL' && deck.Deck) return deck.Deck;
  for (const key of Object.keys(deck)) {
    const candidate = deck[key];
    if (candidate && typeof candidate === 'object' && candidate[name]) {
      return candidate[name];
    }
  }
  return null;
}

async function renderDeckGlView(el, payload) {
  const { deck, JSONConverter, JSONConfiguration } = await ensureDeckGlModules();
  const spec = payload.spec || {};
  const { classNames, enumNames } = collectDeckGlTokens(spec);

  const classes = {};
  classNames.forEach((name) => {
    const resolved = resolveDeckExport(deck, name);
    if (resolved) {
      classes[name] = resolved;
    } else {
      console.warn(`[deckgl] Missing class binding for ${name}.`);
    }
  });

  const enumerations = {};
  enumNames.forEach((name) => {
    const resolved = resolveDeckExport(deck, name);
    if (resolved) {
      enumerations[name] = resolved;
    } else if (deck[name]) {
      enumerations[name] = deck[name];
    } else {
      console.warn(`[deckgl] Missing enumeration binding for ${name}.`);
    }
  });

  const configuration = new JSONConfiguration({
    classes,
    enumerations
  });

  const converter = new JSONConverter({ configuration });
  const clonedSpec = JSON.parse(JSON.stringify(spec));
  const props = converter.convert(clonedSpec) || {};

  if (!props.parent) {
    props.parent = el;
  }

  const hasViewState =
    (props && (props.initialViewState || props.viewState)) ||
    (Array.isArray(props.views) &&
      props.views.some((view) => view && (view.initialViewState || view.viewState)));

  if (typeof props.controller === 'undefined') {
    props.controller = Boolean(hasViewState);
  } else if (props.controller && !hasViewState) {
    console.warn('[deckgl] Controller requested but no view state supplied; disabling controller.');
    props.controller = false;
  }
  if (!props.container) {
    props.container = el;
  }

  // Add default tooltip handler if not provided
  if (!props.getTooltip) {
    props.getTooltip = (info) => {
      if (!info.object) return null;
      const props = [];
      for (const [key, value] of Object.entries(info.object)) {
        if (key !== 'geometry' && key !== 'polygon' && value !== null && value !== undefined) {
          props.push(`${key}: ${value}`);
        }
      }
      return props.length > 0 ? {
        html: `<div style="background: rgba(0,0,0,0.8); color: white; padding: 8px; border-radius: 4px; font-family: monospace; font-size: 12px;">${props.join('<br>')}</div>`
      } : null;
    };
  }

  el.classList.add('deckgl-view');
  el.style.position = 'relative';
  el.style.width = '100%';
  el.style.height = '100%';
  el.style.margin = '0';
  el.style.padding = '0';

  if (el.__deckInstance) {
    console.log('[deckgl] Updating existing Deck instance with new props');
    // Only update, don't recreate
    try {
      el.__deckInstance.setProps(props);
      // Force a redraw to ensure updates are applied
      el.__deckInstance.redraw();
    } catch (err) {
      console.error('[deckgl] Failed to update Deck instance:', err);
      // If update fails, recreate
      el.__deckInstance.finalize();
      delete el.__deckInstance;
      el.innerHTML = '';
      el.__deckInstance = new deck.Deck(props);
    }
  } else {
    console.log('[deckgl] Creating new Deck instance');
    el.innerHTML = '';
    try {
      el.__deckInstance = new deck.Deck(props);
    } catch (err) {
      console.error('[deckgl] Failed to create Deck instance:', err);
      throw err;
    }
  }
}

HTMLWidgets.widget({
  name: "deckgl",
  type: "output",
  factory: function(el, width, height) {
    console.log("[deckgl] — factory() called — element, size:", el, width, height);
    const pending = {};
    let widgetIdInstance = null;
    let handlerRegistered = false;

    function shinyConnector(wid) {
      return {
        query: function(q) {
          console.log(`[deckgl][${wid}] → shinyConnector sending query:`, q);
          return new Promise((resolve, reject) => {
            const reqId = "q" + Math.random().toString(36).substr(2, 9);
            pending[reqId] = { resolve, reject, queryType: q.type || "json" };
            Shiny.setInputValue(
              `${wid}_deckgl_query`,
              { request: reqId, sql: q.sql, type: q.type || "json" },
              { priority: "event" }
            );
          });
        }
      };
    }

    function registerHandler(wid) {
      if (handlerRegistered) {
        console.log(`[deckgl][${wid}] Handler already registered.`);
        return;
      }
      Shiny.addCustomMessageHandler(`${wid}_deckgl_response`, message => {
        console.log(`[deckgl][${wid}] ← shinyConnector received response:`, message);
        const cbEntry = pending[message.request];
        if (!cbEntry) {
          console.warn(`[deckgl][${wid}] Received response for unknown request:`, message.request);
          return;
        }

        if (message.error) {
          console.error(`[deckgl][${wid}] Error from Shiny for request ${message.request}:`, message.error);
          cbEntry.reject(new Error(message.error));
        } else {
          cbEntry.resolve(message.data);
        }
        delete pending[message.request];
      });
      handlerRegistered = true;
      console.log(`[deckgl][${wid}] ✓ Custom message handler registered.`);
    }

    const widgetInstance = {
      renderValue: async function(x) {
        widgetIdInstance = x.widgetId;
        const wid = widgetIdInstance;

        console.log(`[deckgl][${wid}] — renderValue() invoked:`, x);

        if (!handlerRegistered && typeof Shiny !== 'undefined') {
          registerHandler(wid);
        }

        // Store the current spec for potential updates
        el.__lastSpec = x;

        try {
          await renderDeckGlView(el, x);
        } catch (err) {
          console.error(`[deckgl][${wid}] Deck.gl rendering failed:`, err);
          el.innerHTML = `<div style="color:red; padding:10px; font-family:sans-serif;">
            <h4>Deck.gl Rendering Error</h4>
            <p><strong>Message:</strong> ${err.message || err}</p>
          </div>`;
        }
      },
      resize: function(w, h) {
        const wid = widgetIdInstance;
        console.log(`[deckgl][${wid || 'unknown'}] — resize() called: ${w}×${h}.`);
        if (el.__deckInstance) {
          try {
            el.__deckInstance.setProps({ width: w, height: h });
          } catch (err) {
            console.warn(`[deckgl][${wid || 'unknown'}] Deck.gl resize failed:`, err);
          }
        }
      }
    };
    return widgetInstance;
  }
});
