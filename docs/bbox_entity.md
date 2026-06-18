# BBoxEntity

`BBoxEntity` representa una caja delimitadora rotada dentro del editor. La clase mantiene el estado visual con el que trabaja la UI y, cuando hace falta, calcula una versión equivalente en coordenadas de frame para backend o persistencia.

Archivo fuente: `lib/src/bbox_entity.dart`

## Qué modela

La entidad describe un rectángulo rotado con:

- un identificador
- una posición central
- ancho y alto
- un ángulo de rotación
- un color
- una etiqueta opcional

Además conserva una segunda representación en coordenadas de `FRAME`, separada de la representación en `VIEW`.

## Espacios de coordenadas

La clase trabaja con dos sistemas:

- `VIEW`: coordenadas de pantalla o lienzo. Aquí vive el estado editable.
- `FRAME`: coordenadas de la imagen o frame original. Aquí suele vivir el contrato con backend.

Esa separación es la razón de que existan propiedades duplicadas como `center` y `centerF`, o `w` y `wF`.

## Propiedades

### Estado principal en VIEW

- `id`
  - Identificador único de la caja.
  - Si no se pasa al constructor, se genera con `DateTime.now().microsecondsSinceEpoch`.

- `center`
  - Tipo: `Offset`
  - Centro de la caja en coordenadas de vista.
  - Es la posición que usa la UI para dibujar y manipular la bbox.

- `w`
  - Tipo: `double`
  - Ancho de la caja en vista.

- `h`
  - Tipo: `double`
  - Alto de la caja en vista.

- `angle`
  - Tipo: `double`
  - Ángulo de rotación en radianes.
  - Se usa para transformar puntos entre sistema local y sistema global.

- `color`
  - Tipo: `Color`
  - Color visual de la caja.
  - Puede venir del backend en formato hex o BGR.

- `tag`
  - Tipo: `String?`
  - Etiqueta opcional.
  - El comentario en la clase indica que es solo referenciativa.

### Estado derivado en FRAME

Estas propiedades se calculan cuando se llama `setFrameCoords(...)`:

- `centerF`
  - Tipo: `Offset`
  - Centro de la caja en coordenadas de frame.

- `wF`
  - Tipo: `double`
  - Ancho en frame.

- `hF`
  - Tipo: `double`
  - Alto en frame.

- `angleDegScreen`
  - Tipo: `double`
  - Ángulo convertido a grados.
  - Se usa porque el backend espera grados y la UI maneja radianes.

## Constructor

El constructor principal recibe el estado visual de la caja:

```dart
BBoxEntity(
  center: ...,
  w: ...,
  h: ...,
  angle: 0,
  color: const Color(0xff0f52ff),
  tag: ...,
)
```

Notas:

- `angle` es opcional y por defecto vale `0`.
- `color` también tiene un valor por defecto.
- `id` es opcional; si no llega, se autogenera.

## Flujo de datos

### 1. Del servidor hacia la vista

`BBoxEntity.fromServerJson(...)` construye la entidad a partir de JSON del backend.

Lee:

- `id`
- `cx`
- `cy`
- `w`
- `h`
- `tag`
- `angle_deg` o `angle_deg_cv`
- `color_hex` o `color_bgr`

Después:

1. convierte ángulo de grados a radianes
2. convierte color al tipo `Color`
3. transforma `FRAME -> VIEW` con `FitCoverMapper`

Resultado: una `BBoxEntity` lista para dibujarse y editarse en pantalla.

### 2. De la vista hacia backend

`setFrameCoords(FitCoverMapper mapper)` hace la operación inversa:

1. convierte `center` de `VIEW` a `FRAME`
2. convierte `w` y `h` de `VIEW` a `FRAME`
3. convierte `angle` de radianes a grados

Después de esa llamada, la entidad ya tiene listos `centerF`, `wF`, `hF` y `angleDegScreen`.

## Métodos geométricos

### `localToWorld(Offset p)`

Convierte un punto desde el sistema local de la caja al sistema global de la vista.

Uso típico:

- calcular esquinas
- calcular handles
- aplicar rotación sobre puntos relativos al centro

### `worldToLocal(Offset p)`

Hace la conversión inversa: desde la vista global al sistema local de la caja.

Uso típico:

- saber si un punto cae dentro de la bbox
- interpretar interacción del mouse o touch respecto a la caja

### `corners`

Devuelve una lista con las 4 esquinas rotadas de la caja en coordenadas globales.

Orden actual:

1. top-left
2. top-right
3. bottom-right
4. bottom-left

### `handlePositions({double gap = 0})`

Devuelve un `Map<Handle, Offset>` con la posición de:

- esquinas: `tl`, `tr`, `br`, `bl`
- lados: `t`, `r`, `b`, `l`

El parámetro `gap` separa los handles del borde de la caja.

### `rotateHandle([double gap = 24])`

Calcula la posición del handle de rotación por encima de la caja.

### `contains(Offset world)`

Indica si un punto global cae dentro de la caja rotada.

Internamente:

1. transforma el punto a coordenadas locales
2. verifica si está dentro de `w / 2` y `h / 2`

## Helpers de color

### `_colorFromHex(String hex)`

Convierte un string tipo `#RRGGBB` a `Color`.

### `_colorFromBgr(List<int> bgr)`

Convierte una lista `[B, G, R]` a `Color`.

Esto existe porque algunas fuentes externas usan BGR en vez de RGB.

### `colorToHex(Color color, {bool leadingHashSign = true})`

Convierte un `Color` a string hexadecimal tipo `#RRGGBB`.

## `copyWith(...)`

La extensión `BBoxCopy` agrega un `copyWith` para clonar la entidad con cambios parciales.

Esto incluye:

- propiedades base: `center`, `w`, `h`, `angle`, `color`, `tag`
- propiedades derivadas: `centerF`, `wF`, `hF`, `angleDegScreen`

Detalle importante:

- los campos derivados son `late`
- si copias una entidad antes de haber inicializado esos campos y el `copyWith` intenta leerlos, puede lanzar error

## Riesgos y observaciones

- `tag` se castea como `String` en `fromServerJson(...)`, así que hoy se asume que siempre llega con valor.
- `centerF`, `wF`, `hF` y `angleDegScreen` no existen hasta que se llama `setFrameCoords(...)` o se copian desde otra entidad ya inicializada.
- `angleDegScreen` realmente representa el ángulo en grados para backend; el nombre puede inducir a pensar que pertenece solo a pantalla.

## Ejemplo corto

```dart
final box = BBoxEntity(
  center: const Offset(120, 80),
  w: 200,
  h: 100,
  angle: math.pi / 6,
  tag: 'car',
);

box.setFrameCoords(mapper);

print(box.center);          // VIEW
print(box.centerF);         // FRAME
print(box.angle);           // radianes
print(box.angleDegScreen);  // grados
```

## Resumen

`BBoxEntity` es el modelo central de una bounding box rotada. Su responsabilidad principal es mantener una representación editable en vista y permitir la conversión correcta hacia y desde el formato que consume el backend.
