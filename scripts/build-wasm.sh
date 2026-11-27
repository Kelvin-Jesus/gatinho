#!/usr/bin/env bash
# Compila o gato do site (Sources/GatinhoWeb + GatinhoCore) para WebAssembly e grava
# site/wasm/gatinho.wasm. Usa Embedded Swift: sem Foundation e sem o runtime completo,
# o módulo fica em ~270 KB (~120 KB gzip) e só pede clock_time_get e random_get ao WASI.
#
# Precisa de Docker. A imagem (Swift 6.4.3 + SDK wasm) é criada na primeira vez;
# o build fica num volume para não sujar .build/ do Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE=gatinho-wasm
SDK=swift-6.4.3-RELEASE_wasm-embedded
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    docker build -t "$IMAGE" -f ci/wasm.Dockerfile ci
fi

mkdir -p site/wasm
docker run --rm -v "$PWD":/src -v gatinho-wasm-build:/src/.build-wasm "$IMAGE" bash -euo pipefail -c '
    TABLES=$(dirname "$(find /root/.swiftpm/swift-sdks -path "*embedded/wasm32-unknown-wasip1/libswiftUnicodeDataTables.a" | head -1)")
    # reactor: o módulo exporta _initialize e as funções gato_*, sem main.
    # UnicodeDataTables: String/Character (rótulo das teclas) precisam das tabelas no Embedded.
    swift build -c release --product GatinhoWeb --swift-sdk '"$SDK"' \
        --scratch-path .build-wasm/embedded \
        -Xswiftc -Osize \
        -Xswiftc -Xclang-linker -Xswiftc -mexec-model=reactor \
        -Xlinker -L"$TABLES" -Xlinker -lswiftUnicodeDataTables
    wasm-opt -Oz --strip-debug --strip-producers \
        --enable-bulk-memory --enable-sign-ext --enable-nontrapping-float-to-int --enable-mutable-globals \
        .build-wasm/embedded/out/Products/Release-webassembly-wasm32/GatinhoWeb.wasm \
        -o site/wasm/gatinho.wasm 2>&1 | grep -v "memory segments have overlap" || true
    echo "site/wasm/gatinho.wasm: $(wc -c < site/wasm/gatinho.wasm) bytes, $(gzip -9 -c site/wasm/gatinho.wasm | wc -c) gzip"
'
