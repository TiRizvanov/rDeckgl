HTMLWidgets.widget({
  name: 'deckgl',
  type: 'output',

  factory: function(el, width, height) {
    let deckInstance = null;
    let deckContainer = null;

    // RECURSIVE DECODER (ASYNC)
    // Walks the spec looking for our special __arrow_ipc_base64__ or __arrow_url__ flags
    async function resolveData(node) {
      if (Array.isArray(node)) return Promise.all(node.map(resolveData));
      
      if (node && typeof node === 'object') {
        let table = null;

        // CASE A: Static Base64
        if (node.type === '__arrow_ipc_base64__' && node.payload) {
          const binaryString = atob(node.payload);
          const bytes = new Uint8Array(binaryString.length);
          for (let i = 0; i < binaryString.length; i++) {
            bytes[i] = binaryString.charCodeAt(i);
          }
          const Arrow = window.rDeckgl.Arrow;
          table = Arrow.tableFromIPC(bytes);
        }
        // CASE B: Shiny Binary URL
        else if (node.type === '__arrow_url__' && node.url) {
          try {
             const response = await fetch(node.url);
             const arrayBuffer = await response.arrayBuffer();
             const Arrow = window.rDeckgl.Arrow;
             table = Arrow.tableFromIPC(new Uint8Array(arrayBuffer));
          } catch (e) {
             console.error("[deckgl] Failed to fetch Arrow data:", e);
          }
        }

        if (table) {
          // Patch geometry column metadata if missing (DuckDB IPC fallback)
          try {
             const schema = table.schema;
             const geometryField = schema.fields.find(f => f.name === 'geometry');
             if (geometryField) {
                const typeId = geometryField.type.typeId;
                let extensionName = null;
                
                // Binary -> WKB
                if (typeId === 4 || typeId === 15 || typeId === 16) {
                    extensionName = 'geoarrow.wkb';
                } 
                // List -> Polygon (Assumption for now, could be MultiPolygon)
                else if (typeId === 12 || typeId === 19) {
                    extensionName = 'geoarrow.polygon';
                }

                if (extensionName) {
                    if (!geometryField.metadata) {
                       geometryField.metadata = new Map();
                    }
                    if (!geometryField.metadata.get('ARROW:extension:name')) {
                       geometryField.metadata.set('ARROW:extension:name', extensionName);
                    }
                }
             }
          } catch (e) {
             console.warn("[deckgl] Failed to patch Arrow schema:", e);
          }

          return table;
        }

        const result = {};
        // Wait for all keys to resolve
        const keys = Object.keys(node);
        for (const key of keys) {
          result[key] = await resolveData(node[key]);
        }
        return result;
      }
      return node;
    }

    // Helper to transpose column-oriented data (R default) to row-oriented (Deck.gl default)
    function transposeDataFrame(data) {
        if (Array.isArray(data)) return data;
        if (typeof data !== 'object' || data === null) return data;
        
        const keys = Object.keys(data);
        if (keys.length === 0) return [];
        
        // Check if first value is an array
        if (!Array.isArray(data[keys[0]])) return data;

        const length = data[keys[0]].length;
        
        // Check if all values are arrays of same length
        for (const key of keys) {
            if (!Array.isArray(data[key]) || data[key].length !== length) {
                return data; // Not a consistent dataframe
            }
        }
        
        // Transpose
        const rows = new Array(length);
        for (let i = 0; i < length; i++) {
            const row = {};
            for (const key of keys) {
                row[key] = data[key][i];
            }
            rows[i] = row;
        }
        return rows;
    }

    // WKB to Arrow Polygon Vector Converter
    function wkbToPolygonVector(binaryVector) {
        const Arrow = window.rDeckgl.Arrow;
        
        let totalPolys = binaryVector.length;
        let totalRings = 0;
        let totalPoints = 0;
        
        // Pass 1: Count
        for (let i = 0; i < totalPolys; i++) {
            const wkb = binaryVector.get(i); // Uint8Array
            if (!wkb) continue; 
            
            const view = new DataView(wkb.buffer, wkb.byteOffset, wkb.byteLength);
            const littleEndian = view.getUint8(0) === 1;
            const type = view.getUint32(1, littleEndian);
            
            if (type !== 3) { // Polygon (3)
                 // TODO: Handle MultiPolygon (6)
                 console.warn("Not a polygon WKB (type " + type + ")");
                 continue;
            }
            
            const numRings = view.getUint32(5, littleEndian);
            totalRings += numRings;
            
            let offset = 9;
            for (let r = 0; r < numRings; r++) {
                const numPoints = view.getUint32(offset, littleEndian);
                totalPoints += numPoints;
                offset += 4 + (numPoints * 16);
            }
        }
        
        // Allocate
        const polyOffsets = new Int32Array(totalPolys + 1);
        const ringOffsets = new Int32Array(totalRings + 1);
        const coords = new Float64Array(totalPoints * 2);
        
        let currentPolyOffset = 0;
        let currentRingOffset = 0;
        let currentCoordIndex = 0;
        
        polyOffsets[0] = 0;
        ringOffsets[0] = 0;
        
        // Pass 2: Fill
        let ringIndex = 0;
        
        for (let i = 0; i < totalPolys; i++) {
            const wkb = binaryVector.get(i);
            if (!wkb) {
                 polyOffsets[i+1] = polyOffsets[i];
                 continue;
            }
            
            const view = new DataView(wkb.buffer, wkb.byteOffset, wkb.byteLength);
            const littleEndian = view.getUint8(0) === 1;
            const numRings = view.getUint32(5, littleEndian);
            
            let offset = 9;
            for (let r = 0; r < numRings; r++) {
                const numPoints = view.getUint32(offset, littleEndian);
                offset += 4;
                
                for (let p = 0; p < numPoints; p++) {
                    coords[currentCoordIndex++] = view.getFloat64(offset, littleEndian);
                    coords[currentCoordIndex++] = view.getFloat64(offset + 8, littleEndian);
                    offset += 16;
                }
                
                currentRingOffset += numPoints;
                ringOffsets[++ringIndex] = currentRingOffset;
            }
            
            currentPolyOffset += numRings;
            polyOffsets[i+1] = currentPolyOffset;
        }
        
        // Construct Arrow Data
        // Point: FixedSizeList<2, Float64>
        const pointDataType = new Arrow.FixedSizeList(2, new Arrow.Field('xy', new Arrow.Float64()));
        const pointData = Arrow.makeData({
            type: pointDataType,
            length: totalPoints,
            child: Arrow.makeData({
                type: new Arrow.Float64(),
                length: totalPoints * 2,
                data: coords
            })
        });
        
        // Ring: List<Point>
        const ringDataType = new Arrow.List(new Arrow.Field('points', pointDataType));
        const ringData = Arrow.makeData({
            type: ringDataType,
            length: totalRings,
            valueOffsets: ringOffsets,
            child: pointData
        });
        
        // Polygon: List<Ring>
        const polyDataType = new Arrow.List(new Arrow.Field('rings', ringDataType));
        
        const polyData = Arrow.makeData({
            type: polyDataType,
            length: totalPolys,
            valueOffsets: polyOffsets,
            child: ringData
        });
        
        const vec = Arrow.makeVector(polyData);
        // Manually set extension name on the vector's type if possible, or rely on the data
        // GeoArrow layers check the type of the vector.
        // We need to ensure the schema/field has the metadata.
        // But makeVector creates a vector with a type.
        // We can wrap it?
        return vec;
    }

    return {
      renderValue: function(x) {
        // Safety check: ensure el is a valid DOM node
        if (!el || !el.appendChild) {
          console.error("[deckgl] Invalid container element");
          return;
        }
        
        // 1. Use or create a stable container div for deck.gl (Synchronous)
        // This prevents deck.gl from interfering with htmlwidgets' MutationObserver
        if (!deckContainer) {
             // Check if there's already a child div (Shiny creates one)
             if (el.children.length > 0 && el.children[0].tagName === 'DIV') {
                 deckContainer = el.children[0];
             } else {
                 deckContainer = document.createElement('div');
                 deckContainer.style.width = '100%';
                 deckContainer.style.height = '100%';
                 deckContainer.style.position = 'relative';
                 el.appendChild(deckContainer);
             }
        }
        
        // 2. Initialize Deck immediately if needed (Synchronous)
        if (!deckInstance) {
             try {
                 const initialProps = {
                     parent: deckContainer,  // Use 'parent' instead of 'container' to ensure canvas is appended
                     width: width,
                     height: height,
                     useDevicePixels: true,
                     onError: (e) => console.error("[deckgl] Deck error:", e),
                     // Extract initialViewState if present
                     initialViewState: x.spec.initialViewState,
                     controller: x.spec.controller,
                     layers: [] // Start with empty layers
                 };
                 deckInstance = new window.rDeckgl.Deck(initialProps);
             } catch (e) {
                 console.error("[deckgl] Init error:", e);
             }
        }

        // 3. Convert Spec to Deck Props (Async)
        resolveData(x.spec).then(resolvedSpec => {
             
             // Map layer strings to actual classes
             if (resolvedSpec.layers) {
                resolvedSpec.layers = resolvedSpec.layers.map(layerSpec => {
                   // e.g. "GeoArrowScatterplotLayer"
                   const layerType = layerSpec['@@type'];
                   const LayerClass = window.rDeckgl.Layers[layerType];
                   
                   if(!LayerClass) {
                     console.error("Unknown layer:", layerType);
                     return null;
                   }

                   const { '@@type': _, ...props } = layerSpec;
                   
                   // Transpose data if needed
                   if (props.data) {
                       props.data = transposeDataFrame(props.data);
                   }

                   // Resolve Column Accessors (e.g. "@@col:geometry")
                   // This allows passing Arrow Vectors directly to GeoArrow layers
                   if (props.data && typeof props.data.getChild === 'function') {
                       for (const key in props) {
                           if (typeof props[key] === 'string' && props[key].startsWith('@@col:')) {
                               const colName = props[key].substring(6);
                               let col = props.data.getChild(colName);
                               if (col) {
                                   // Check if it is a binary column (WKB)
                                   // In Apache Arrow JS, Binary is typeId 4, LargeBinary is 15, FixedSizeBinary is 16
                                   const typeId = col.typeId !== undefined ? col.typeId : (col.type ? col.type.typeId : undefined);

                                   if (layerType === 'GeoArrowSolidPolygonLayer' && (typeId === 4 || typeId === 15 || typeId === 16)) { 
                                       try {
                                           col = wkbToPolygonVector(col);
                                       } catch (e) {
                                           console.error("[deckgl] WKB conversion failed:", e);
                                       }
                                   }
                                   
                                   props[key] = col;
                               } else {
                                   console.warn(`[deckgl] Column accessor ${key} failed: column ${colName} not found.`);
                               }
                           }
                       }
                   }

                   // Special handling for GeoJsonLayer with Arrow Data (from DuckDB ST_AsGeoJSON)
                   if (layerType === 'GeoJsonLayer' && props.data && props.data.schema) {
                       const table = props.data;
                       const features = [];
                       
                       // Find geometry column (assume 'geometry' or first column)
                       let geomColName = 'geometry';
                       if (!table.getChild(geomColName)) {
                           geomColName = table.schema.fields[0].name;
                       }
                       const geomCol = table.getChild(geomColName);
                       
                       if (geomCol) {
                           for(let i=0; i<table.numRows; i++) {
                               const geomStr = geomCol.get(i);
                               let geom = null;
                               try {
                                   geom = JSON.parse(geomStr);
                               } catch(e) {
                                   console.warn("Failed to parse GeoJSON geometry at row " + i, e);
                                   continue;
                               }
                               
                               const properties = {};
                               table.schema.fields.forEach(f => {
                                   if (f.name !== geomColName) {
                                       properties[f.name] = table.getChild(f.name).get(i);
                                   }
                               });
                               
                               features.push({
                                   type: "Feature",
                                   geometry: geom,
                                   properties: properties
                               });
                           }
                           props.data = features;
                       } else {
                           console.warn("[deckgl] No geometry column found for GeoJsonLayer conversion.");
                       }
                   }

                   return new LayerClass(props);
                }).filter(l => l);
             }
             
             // 4. Update Deck
             if (deckInstance) {
                deckInstance.setProps(resolvedSpec);
             }

        }).catch(e => {
            console.error("[deckgl] Error resolving spec:", e);
        });
      },

      resize: function(width, height) {
        if (deckInstance) {
          deckInstance.setProps({ width, height });
        }
      }
    };
  }
});