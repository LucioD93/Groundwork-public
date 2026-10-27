# Groundwork app icon

The production source is `App/AppIcon.icon`. Its three editable SVG layers retain the original icon’s cup with a right handle, two steam wisps, and three beans. The SVGs contain no baked shadows or highlights. The Icon Composer document supplies native specular lighting, translucent material, shadows, and appearance-specific colors.

| Role | Light | Dark |
| --- | --- | --- |
| Background | Porcelain `#faf0e8` → warm cream `#ead9cc` | Cocoa `#342520` → deep cocoa `#211715` |
| Cup | Terracotta `#9e4e35` | Soft terracotta `#e6a18a` |
| Steam | Warm taupe `#795d52` | Oat `#d0afa0` |
| Beans | Roasted cocoa `#5d3d30` | Toasted cream `#d1ac8b` |

The system renders the clear/tinted versions from these same layers. Home Screen appearance controls icon switching independently of the in-app appearance preference. No alternate-icon API, confirmation alert, or app launch is required for system appearance switching. Xcode 26+ compiles the resource and generates earlier-iOS fallback images; the deployment target remains iOS 17.

## Artwork process

Built-in imagegen was used for foreground exploration. The production artwork was then recreated as clean SVG paths to keep small icon edges smooth and remove raster transparency artifacts. The generated raster candidates are not shipped.

Original shape-exploration prompt (the production colors now use Terracotta & Cocoa):

> Production app icon foreground graphic, flat vector icon style. On a genuinely transparent alpha background, draw an elegant solid purple (#8839ef) coffee cup with its handle on the right, two detached curling purple steam wisps above, and three distinct purple coffee bean shapes at its lower left. Use negative transparent space for the oval opening of the cup, the handle hole, and a single broad curved slit through each coffee bean. Bold simple shapes with smooth edges, centered with generous outer margins. No background plate, gradients, shadows, lighting, texture, noise, or text. The graphic is a foreground mask for Apple’s native Liquid Glass renderer.

## Export a reference image

From the repository root, with full Xcode installed:

```sh
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  App/AppIcon.icon --export-image --output-file output/icon-terracotta-light.png \
  --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
```

Use `--rendition Dark` for the dark cocoa version, `ClearLight` / `ClearDark` for clear, and `TintedLight` / `TintedDark` for tinted reference exports. These PNGs include the system’s icon mask and are reference images; ship the layered `.icon` resource in the app.

References: [Apple’s Icon Composer documentation](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).
