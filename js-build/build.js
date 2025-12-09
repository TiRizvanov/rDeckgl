const esbuild = require('esbuild');

const deckGlTypedAliasPlugin = {
  name: 'deck-gl-typed-alias',
  setup(build) {
    build.onResolve({ filter: /^@deck\.gl\/core\/typed$/ }, () => ({
      path: require.resolve('@deck.gl/core'),
    }));
    build.onResolve({ filter: /^@deck\.gl\/layers\/typed$/ }, () => ({
      path: require.resolve('@deck.gl/layers'),
    }));
  },
};

esbuild.build({
  entryPoints: ['src/index.js'],
  bundle: true,
  outfile: '../inst/htmlwidgets/lib/deckgl/deckgl-bundle.js', // Output directly to package inst
  format: 'iife', 
  globalName: 'rDeckglBundle', // wrapper variable
  minify: false,
  sourcemap: true,
  target: ['es2020'], // Modern browsers for BigInt support
  plugins: [deckGlTypedAliasPlugin]
}).catch(() => process.exit(1));
