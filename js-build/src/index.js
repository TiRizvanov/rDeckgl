import { Deck } from '@deck.gl/core';
import * as CoreLayers from '@deck.gl/layers';
import * as GeoLayers from '@deck.gl/geo-layers';
import * as GeoArrowLayers from '@geoarrow/deck.gl-layers';
import * as Arrow from 'apache-arrow';

// Merge all layers into a single object for easy access via R
const Layers = {
  ...CoreLayers,
  ...GeoLayers,
  ...GeoArrowLayers
};

// Attach to window so the HTMLWidget can find it
window.rDeckgl = {
  Deck,
  Layers,
  Arrow
};