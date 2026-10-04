ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base-debian:bookworm

# ---- build the open-source Brother SANE backend ----
FROM ${BUILD_FROM} AS brscan-build

ARG BRSCAN_REPO=https://github.com/peloycosta/brscan.git
ARG BRSCAN_COMMIT=f49d1e56b342ca66534d2be1924f678a974281c6

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential cmake pkg-config git ca-certificates \
        libsane-dev libusb-1.0-0-dev libusb-dev libjpeg-dev libncurses-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git init /src \
    && git -C /src fetch --depth 1 "${BRSCAN_REPO}" "${BRSCAN_COMMIT}" \
    && git -C /src checkout --detach FETCH_HEAD \
    && test "$(git -C /src rev-parse HEAD)" = "${BRSCAN_COMMIT}"

RUN cmake -S /src -B /build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /build -j"$(nproc)" \
    && DESTDIR=/out cmake --install /build \
    && ln -sf libbrscandec.so /out/usr/lib/libbrscandec2.so \
    && ln -sf libbrcolm.so /out/usr/lib/libbrcolm2.so \
    && ln -sf Brsane.ini /out/usr/share/sane/brother/Brsane2.ini \
    && test -f /out/usr/lib/sane/libsane-brother.so.1 \
    && test -f /out/usr/lib/libbrscandec.so.1 \
    && test -f /out/usr/lib/libbrcolm.so.1

# ---- runtime: SANE + scanservjs ----
FROM ${BUILD_FROM}

ARG SCANSERVJS_VERSION=3.3.0
ARG SCANSERVJS_SHA256=d57a26fa6472651ac5c780a4057ae944361cfcaa7c0b6d07a7856e7ef6b15f75

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl adduser \
        sane-utils libsane1 libusb-1.0-0 libusb-0.1-4 libjpeg62-turbo usbutils \
        nodejs imagemagick ghostscript tesseract-ocr tesseract-ocr-eng smbclient \
    && curl -fsSL -o /tmp/scanservjs.deb \
        "https://github.com/sbs20/scanservjs/releases/download/v${SCANSERVJS_VERSION}/scanservjs_${SCANSERVJS_VERSION}-1_all.deb" \
    && echo "${SCANSERVJS_SHA256}  /tmp/scanservjs.deb" | sha256sum -c - \
    && apt-get install -y --no-install-recommends /tmp/scanservjs.deb \
    && rm -f /tmp/scanservjs.deb \
    && rm -rf /var/lib/apt/lists/*

# scanservjs pipes file lists to `convert @-`; Debian's ImageMagick 6 policy blocks indirect reads.
RUN sed -i 's/policy domain="path" rights="none" pattern="@\*"/policy domain="path" rights="read" pattern="@*"/' \
        /etc/ImageMagick-6/policy.xml \
    && grep -q 'rights="read" pattern="@\*"' /etc/ImageMagick-6/policy.xml \
    && grep -q 'rights="read | write" pattern="PDF"' /etc/ImageMagick-6/policy.xml

COPY --from=brscan-build /out/ /

# Debian's SANE dll loader only looks in the multiarch backend dir.
RUN set -e; \
    dirs=$(ls -d /usr/lib/*-linux-gnu/sane); \
    test "$(echo "$dirs" | wc -l)" = 1; \
    ln -sf /usr/lib/sane/libsane-brother.so.1 "$dirs/libsane-brother.so.1"; \
    ldconfig; \
    echo brother > /etc/sane.d/dll.conf; \
    rm -f /etc/sane.d/dll.d/*

COPY config.local.js /etc/scanservjs/config.local.js
COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]
