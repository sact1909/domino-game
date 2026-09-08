# Iconos

El juego usa seis iconos de Lucide: `check`, `info`, `play`, `settings`, `star` y
`users`. Están acá, y son los únicos que Godot importa y que viajan en el ejecutable.

En `_lucide/` está el set completo (1816 archivos), como biblioteca de la que sacar.

El `.gdignore` que hay en `_lucide/` hace que **Godot la ignore por completo**: no
importa nada de acá y nada de acá entra en el juego exportado. Es a propósito. Sin él,
Godot importaría los 1816 iconos —lo que alarga cada importación del proyecto— y el
preset de exportación, que se lleva todos los recursos, los metería en el ejecutable:
2.4 MB de iconos para usar seis.

## Cómo usar uno más

1. Copiarlo un nivel arriba, a `assets/icons/`.
2. **Cambiarle `currentColor` por `#ffffff`.** Lucide publica el trazo como
   `stroke="currentColor"`, que sin hoja de estilos se rasteriza en NEGRO; el color se
   aplica con `modulate`, que multiplica, y negro por cualquier color sigue siendo
   negro. Sin este paso el icono sale invisible sobre el cartel oscuro.
3. Darle un nombre en `Ui.ICON_FILES`.

Ahí sí lo importa Godot y ahí sí viaja en la build.

## Licencia

Lucide es ISC, que permite usarlo sin condiciones salvo conservar el aviso de copyright.
Ese aviso NO vino en la descarga: hay que traer el archivo `LICENSE` de
https://github.com/lucide-icons/lucide y ponerlo junto a los iconos.
