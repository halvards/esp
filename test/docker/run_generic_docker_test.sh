# Copyright (C) Endpoints Server Proxy Authors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
################################################################################
#

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Load error handling utilities
. ${ROOT}/script/all-utilities || { echo "Cannot load Bash utilities" ; exit 1 ; }

PORT=''
SSL_PORT=''
NGINX_STATUS_PORT=''
SERVER_ADDRESS=''
NGINX_CONF_PATH=''
PUBLISH='--publish-all'
BACKEND="${ROOT}/test/docker/backend"
VOLUMES='--volumes-from=app'
VOLUMES+=" --volume=${BACKEND}/service.json:/etc/nginx/endpoints/service.json"
SERVICE_NAME=''
SERVICE_VERSION=''

while getopts 'a:n:N:p:S:s:v:' arg; do
  case ${arg} in
    a) SERVER_ADDRESS="${OPTARG}";;
    s) SERVICE_NAME="${OPTARG}";;
    v) SERVICE_VERSION="${OPTARG}";;
    n) NGINX_CONF_PATH="${OPTARG}";;
    N) NGINX_STATUS_PORT="${OPTARG}";;
    p) PORT="${OPTARG}";;
    S) SSL_PORT="${OPTARG}";;
  esac
done

if [[ -z "${SERVICE_NAME}" ]]; then
  echo "-s SERVICE_NAME must be provided!"
  exit 2
fi

if [[ -z "${SERVICE_VERSION}" ]]; then
  echo "-v SERVICE_VERSION must be provided!"
  exit 2
fi

ARGS=()
DIR="${ROOT}/test/docker/esp_generic"

[[ -n "${PORT}" ]]              && ARGS+=(-p "${PORT}")
[[ -n "${SSL_PORT}" ]]          && {
  ARGS+=(-S "${SSL_PORT}");
  PUBLISH+=" --expose=${SSL_PORT}";
  VOLUMES+=" --volume=${DIR}/nginx.key:/etc/nginx/ssl/nginx.key";
  VOLUMES+=" --volume=${DIR}/nginx.crt:/etc/nginx/ssl/nginx.crt";
}
[[ -n "${SERVER_ADDRESS}" ]]    && ARGS+=(-a "${SERVER_ADDRESS}")
[[ -n "${NGINX_STATUS_PORT}" ]] && {
  ARGS+=(-N "${NGINX_STATUS_PORT}");
  PUBLISH+=" --expose=${NGINX_STATUS_PORT}";
}
[[ -n "${NGINX_CONF_PATH}" ]]   && {
  ARGS+=(-n "${NGINX_CONF_PATH}");
  VOLUMES+=" --volume=${DIR}/custom_nginx.conf:/etc/nginx/custom/nginx.conf";
}
[[ -n "${SERVICE_NAME}" ]]      && ARGS+=(-s "${SERVICE_NAME}")
[[ -n "${SERVICE_VERSION}" ]]   && ARGS+=(-v "${SERVICE_VERSION}")

# Start Endpoints proxy container.
docker run \
    --name=esp \
    --detach=true \
    ${PUBLISH} \
    --link=metadata:metadata \
    --link=control:control \
    --link=app:app \
    ${VOLUMES} \
    --entrypoint=/var/lib/nginx/bin/start_nginx.sh \
    esp-image \
    ${ARGS[@]} \
  || error_exit "Cannot start Endpoints proxy container."

function wait_for() {
  local URL=${1}

  for (( I=0 ; I<60 ; I++ )); do
    printf "\nWaiting for ${URL}\n"
    curl --silent ${URL} && return 0
    sleep 1
  done
  return 1
}

function start_esp_test() {
  local TARGET_ADDRESS=${1}

  curl -v -k ${TARGET_ADDRESS}/shelves
  SHELVES_RESULT=$?
  SHELVES_BODY=$(curl --silent -k ${TARGET_ADDRESS}/shelves)

  curl -v -k ${TARGET_ADDRESS}/shelves/1/books
  BOOKS_RESULT=$?
  BOOKS_BODY=$(curl --silent -k ${TARGET_ADDRESS}/shelves/1/books)

  echo "Shelves result: ${SHELVES_RESULT}"
  echo "Books result: ${BOOKS_RESULT}"

  [[ "${SHELVES_BODY}" == *"\"Fiction\""* ]] \
    || error_exit "/shelves did not return Fiction: ${SHELVES_BODY}"
  [[ "${SHELVES_BODY}" == *"\"Fantasy\""* ]] \
    || error_exit "/shelves did not return Fantasy: ${SHELVES_BODY}"
  ERROR_MESSAGE="/shelves/1/books did not return unregistered callers"
  [[ "${BOOKS_BODY}" == *"Method doesn't allow unregistered callers"* ]] \
    || error_exit "$ERROR_MESSAGE: ${BOOKS_RESULT}"

  [[ ${SHELVES_RESULT} -eq 0 ]] \
    && [[ ${BOOKS_RESULT} -eq 0 ]] \
    || error_exit "Test failed."
}

# Default nginx status port is 8090.
[[ -n "${NGINX_STATUS_PORT}" ]] || NGINX_STATUS_PORT=8090

ESP_NGINX_STATUS_PORT=$(docker port esp $NGINX_STATUS_PORT) \
  || error_exit "Cannot get esp nginx status port number."

if [[ "$(uname)" == "Darwin" ]]; then
  IP=$(docker-machine ip default)
  ESP_NGINX_STATUS_PORT=${IP}:${ESP_NGINX_STATUS_PORT##*:}
fi

printf "\nCheck esp status port.\n"
wait_for "${ESP_NGINX_STATUS_PORT}/nginx_status" \
  || error_exit "ESP container didn't come up."

# By default, ESP listens at port 8080 for http requests.
[[ -n "${PORT}" ]] || PORT=8080

ESP_PORT=$(docker port esp $PORT) \
  || error_exit "Cannot get esp port number."

if [[ "$(uname)" == "Darwin" ]]; then
  IP=$(docker-machine ip default)
  ESP_PORT=${IP}:${ESP_PORT##*:}
fi

printf "\nStart testing esp http requests.\n"
start_esp_test "${ESP_PORT}"

if [[ "${SSL_PORT}" ]]; then
  printf "\nStart testing esp https requests.\n"
  ESP_SSL_PORT=$(docker port esp $SSL_PORT) \
    || error_exit "Cannot get esp ssl port number."
  start_esp_test "https://${ESP_SSL_PORT}"
fi

UUID="$(uuidgen)"
ELOG=~/error-${UUID}.log
ALOG=~/access-${UUID}.log
docker cp esp:/var/log/nginx/error.log "${ELOG}"
docker cp esp:/var/log/nginx/access.log "${ALOG}"
echo "Logs saved into ${ELOG}, ${ALOG}"
printf "\nNGINX error log:\n"
cat ${ELOG}

printf "\n\nShutting down esp.\n"
docker stop esp
docker rm esp