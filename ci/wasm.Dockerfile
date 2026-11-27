# Swift 6.4.3 + SDK wasm (inclui o Embedded) para compilar o gato do site; usado por scripts/build-wasm.sh.
FROM swift:6.4.3-noble
RUN swift sdk install \
      https://download.swift.org/swift-6.4.3-release/wasm-sdk/swift-6.4.3-RELEASE/swift-6.4.3-RELEASE_wasm.artifactbundle.tar.gz \
      --checksum 5f24408dc9737ce4cb23b7e3ed4306cabfa02cc02f22ab260b14579b955d4b12 \
 && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends binaryen brotli \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
