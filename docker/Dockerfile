# Servidor dedicado de Dominó Dominicano.
#
# Build en dos etapas: la primera baja el editor de Godot y sus export templates
# para exportar el proyecto; la segunda solo carga el binario resultante.
#
# Construir en local:
#   docker build -f docker/Dockerfile -t domino-server .
#   docker run --rm -p 8080:8080 domino-server
#
# En Coolify: build pack "Dockerfile", con la ruta docker/Dockerfile y el contexto
# en la raíz del repo.

ARG GODOT_VERSION=4.7.2
ARG GODOT_RELEASE=stable
# Debe coincidir con el nombre del preset en export_presets.cfg (el que genera el
# editor por defecto se llama "Linux", con dedicated_server=true).
ARG EXPORT_PRESET="Linux"
# Puerto por defecto del contenedor. En Coolify se sobrescribe con la variable de
# entorno PORT; esto solo define el valor si nadie la pasa.
ARG SERVER_PORT=8090


# ---------------------------------------------------------------------------
# Etapa 1: exportar el proyecto
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS build

ARG GODOT_VERSION
ARG GODOT_RELEASE
ARG EXPORT_PRESET

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*

# Editor headless
RUN curl -fsSL -o /tmp/godot.zip \
      "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64.zip" \
 && unzip -q /tmp/godot.zip -d /tmp/godot \
 && mv "/tmp/godot/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64" /usr/local/bin/godot \
 && chmod +x /usr/local/bin/godot \
 && rm -rf /tmp/godot.zip /tmp/godot

# Export templates: Godot los busca en esta ruta exacta, con el nombre
# "<version>.<release>" (por ejemplo 4.7.2.stable).
RUN curl -fsSL -o /tmp/templates.tpz \
      "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_export_templates.tpz" \
 && mkdir -p /root/.local/share/godot/export_templates \
 && unzip -q /tmp/templates.tpz -d /tmp/tpl \
 && mv /tmp/tpl/templates "/root/.local/share/godot/export_templates/${GODOT_VERSION}.${GODOT_RELEASE}" \
 && rm -rf /tmp/templates.tpz /tmp/tpl

WORKDIR /src
COPY . .

# Primero se importan los recursos (genera .godot/). Devuelve código distinto de 0
# ante avisos que no impiden exportar, así que no se corta el build por eso.
RUN godot --headless --import || true

RUN mkdir -p /out \
 && godot --headless --export-release "${EXPORT_PRESET}" /out/domino_server \
 && chmod +x /out/domino_server


# ---------------------------------------------------------------------------
# Etapa 2: runtime
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG SERVER_PORT

# La plantilla "dedicated server" viene sin drivers de video ni audio, así que las
# dependencias son mínimas. Si el binario se queja de alguna librería, "ldd
# domino_server" dentro del contenedor dice exactamente cuál falta.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libstdc++6 \
 && rm -rf /var/lib/apt/lists/*

# Usuario sin privilegios: el servidor no necesita root para escuchar en 8080.
RUN useradd --create-home --shell /usr/sbin/nologin domino
USER domino

WORKDIR /app
COPY --from=build --chown=domino:domino /out/ /app/

ENV PORT=${SERVER_PORT}
EXPOSE ${SERVER_PORT}

CMD ["/app/domino_server", "--headless", "--", "--server"]
