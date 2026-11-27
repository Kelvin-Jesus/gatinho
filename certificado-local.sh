#!/bin/bash
# Cria (uma vez) o certificado "Gatinho Dev" no chaveiro de login para assinar o app.
# Com assinatura fixa, o macOS mantém a permissão de Acessibilidade entre recompilações;
# a assinatura ad hoc muda a cada build e a permissão antiga deixa de valer.
# O certificado é autoassinado, confiável só para assinar código e só nesta máquina.
set -euo pipefail
NAME="Gatinho Dev"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "Certificado \"$NAME\" já existe."
  exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cfg" <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CFG
# /usr/bin/openssl (LibreSSL) gera um .p12 que o `security` do macOS aceita.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cfg" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -passout pass:gatinho -out "$TMP/id.p12"
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P gatinho -T /usr/bin/codesign
# Sem confiança explícita o macOS ignora a permissão de Acessibilidade dada ao app.
# Vale só para assinar código, só neste usuário; o macOS pede a senha para aprovar.
security add-trusted-cert -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$TMP/cert.pem"
echo "Certificado \"$NAME\" criado no chaveiro de login."
