#!/bin/bash

set -e

export PSONO_DOCKER_PREFIX='psono-docker'

# Function to set the installation directory
set_install_dir() {
  INSTALL_DIR='/opt'
  export INSTALL_DIR

  echo "Where do you want Psono to be installed..."
  read -p "INSTALL_DIR [default: $INSTALL_DIR]: " INSTALL_DIR_NEW
  if [ "$INSTALL_DIR_NEW" != "" ]; then
    INSTALL_DIR=$INSTALL_DIR_NEW
  fi

  mkdir -p $INSTALL_DIR
  cd $INSTALL_DIR
  rm -Rf $INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX
  mkdir -p $INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX
}

# Function to ask for user parameters
ask_parameters() {
  if [ -f "$INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX/.psonoenv" ]; then
    set -o allexport
    source $INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX/.psonoenv
    set +o allexport
  else
    export PSONO_PROTOCOL="http://"
    export PSONO_VERSION=EE
    export PSONO_EXTERNAL_PORT=80
    export PSONO_EXTERNAL_PORT_SECURE=443
    export PSONO_POSTGRES_PORT=5432
    export PSONO_POSTGRES_PASSWORD=$(date +%s | sha256sum | base64 | head -c 16)
    export PSONO_USERDOMAIN=localhost
    export PSONO_WEBDOMAIN='psono.local'
    export PSONO_POSTGRES_USER=postgres
    export PSONO_POSTGRES_DB=postgres
    export PSONO_POSTGRES_HOST=$PSONO_DOCKER_PREFIX-psono-postgres
    export PSONO_INSTALL_ACME=0
  fi

  read -p "PSONO_VERSION [default: $PSONO_VERSION]: " PSONO_VERSION_NEW
  if [ "$PSONO_VERSION_NEW" != "" ]; then
    export PSONO_VERSION=$PSONO_VERSION_NEW
  fi

  if [[ ! $PSONO_VERSION =~ ^(DEV|EE|CE)$ ]]; then
    echo "unknown PSONO_VERSION: $PSONO_VERSION" >&2
    exit 1
  fi

  read -p "PSONO_EXTERNAL_PORT [default: $PSONO_EXTERNAL_PORT]: " PSONO_EXTERNAL_PORT_NEW
  if [ "$PSONO_EXTERNAL_PORT_NEW" != "" ]; then
    export PSONO_EXTERNAL_PORT=$PSONO_EXTERNAL_PORT_NEW
  fi

  read -p "PSONO_EXTERNAL_PORT_SECURE [default: $PSONO_EXTERNAL_PORT_SECURE]: " PSONO_EXTERNAL_PORT_SECURE_NEW
  if [ "$PSONO_EXTERNAL_PORT_SECURE_NEW" != "" ]; then
    export PSONO_EXTERNAL_PORT_SECURE=$PSONO_EXTERNAL_PORT_SECURE_NEW
  fi

  read -p "PSONO_POSTGRES_PORT [default: $PSONO_POSTGRES_PORT]: " PSONO_POSTGRES_PORT_NEW
  if [ "$PSONO_POSTGRES_PORT_NEW" != "" ]; then
    export PSONO_POSTGRES_PORT=$PSONO_POSTGRES_PORT_NEW
  fi

  read -p "PSONO_POSTGRES_USER [default: $PSONO_POSTGRES_USER]: " PSONO_POSTGRES_USER_NEW
  if [ "$PSONO_POSTGRES_USER_NEW" != "" ]; then
    export PSONO_POSTGRES_USER=$PSONO_POSTGRES_USER_NEW
  fi

  read -p "PSONO_POSTGRES_DB [default: $PSONO_POSTGRES_DB]: " PSONO_POSTGRES_DB_NEW
  if [ "$PSONO_POSTGRES_DB_NEW" != "" ]; then
    export PSONO_POSTGRES_DB=$PSONO_POSTGRES_DB_NEW
  fi

  read -p "PSONO_POSTGRES_HOST [default: $PSONO_POSTGRES_HOST]: " PSONO_POSTGRES_HOST_NEW
  if [ "$PSONO_POSTGRES_HOST_NEW" != "" ]; then
    export PSONO_POSTGRES_HOST=$PSONO_POSTGRES_HOST_NEW
  fi

  read -p "PSONO_POSTGRES_PASSWORD [default: $PSONO_POSTGRES_PASSWORD]: " PSONO_POSTGRES_PASSWORD_NEW
  if [ "$PSONO_POSTGRES_PASSWORD_NEW" != "" ]; then
    export PSONO_POSTGRES_PASSWORD=$PSONO_POSTGRES_PASSWORD_NEW
  fi

  read -p "PSONO_WEBDOMAIN [default: $PSONO_WEBDOMAIN]: " PSONO_WEBDOMAIN_NEW
  if [ "$PSONO_WEBDOMAIN_NEW" != "" ]; then
    export PSONO_WEBDOMAIN=$PSONO_WEBDOMAIN_NEW
  fi

  read -p "PSONO_USERDOMAIN [default: $PSONO_USERDOMAIN]: " PSONO_USERDOMAIN_NEW
  if [ "$PSONO_USERDOMAIN_NEW" != "" ]; then
    export PSONO_USERDOMAIN=$PSONO_USERDOMAIN_NEW
  fi

  read -p "PSONO_INSTALL_ACME [default: $PSONO_INSTALL_ACME]: " PSONO_INSTALL_ACME_NEW
  if [ "$PSONO_INSTALL_ACME_NEW" != "" ]; then
    export PSONO_INSTALL_ACME=$PSONO_INSTALL_ACME_NEW
  fi

  rm -Rf $INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX/.psonoenv

  cat <<EOF > $INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX/.psonoenv
PSONO_VERSION='${PSONO_VERSION}'
PSONO_EXTERNAL_PORT='${PSONO_EXTERNAL_PORT}'
PSONO_EXTERNAL_PORT_SECURE='${PSONO_EXTERNAL_PORT_SECURE}'
PSONO_POSTGRES_PORT='${PSONO_POSTGRES_PORT}'
PSONO_POSTGRES_PASSWORD='${PSONO_POSTGRES_PASSWORD}'
PSONO_USERDOMAIN='${PSONO_USERDOMAIN}'
PSONO_WEBDOMAIN='${PSONO_WEBDOMAIN}'
PSONO_POSTGRES_USER='${PSONO_POSTGRES_USER}'
PSONO_POSTGRES_DB='${PSONO_POSTGRES_DB}'
PSONO_POSTGRES_HOST='${PSONO_POSTGRES_HOST}'
EOF

  cp $INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX/.psonoenv $INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX/.env
}

# Function to craft the Docker Compose file
craft_docker_compose_file() {
    echo "Crafting docker compose file"

    cat <<EOF > $INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX/docker-compose.yml
version: "2"
services:
  proxy:
    container_name: '${PSONO_DOCKER_PREFIX}-psono-proxy'
    restart: "always"
    image: "nginx:alpine"
    ports:
      - "${PSONO_EXTERNAL_PORT}:80"
      - "${PSONO_EXTERNAL_PORT_SECURE}:443"
    depends_on:
      - psono-server
      - psono-fileserver
      - psono-client
    links:
      - psono-server:${PSONO_DOCKER_PREFIX}-psono-server
      - psono-fileserver:${PSONO_DOCKER_PREFIX}-psono-fileserver
      - psono-client:${PSONO_DOCKER_PREFIX}-psono-server
    volumes:
      - $INSTALL_DIR/psono/html:/var/www/html
      - $INSTALL_DIR/psono/certificates/dhparam.pem:/etc/ssl/dhparam.pem
      - $INSTALL_DIR/psono/certificates/private.key:/etc/ssl/private.key
      - $INSTALL_DIR/psono/certificates/public.crt:/etc/ssl/public.crt
      - $INSTALL_DIR/psono/config/psono_proxy_nginx.conf:/etc/nginx/nginx.conf

  postgres:
    container_name: ${PSONO_DOCKER_PREFIX}-psono-postgres
    restart: "always"
    image: "postgres:12-alpine"
    environment:
      POSTGRES_USER: "${PSONO_POSTGRES_USER}"
      POSTGRES_PASSWORD: "${PSONO_POSTGRES_PASSWORD}"
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
    volumes:
      - $INSTALL_DIR/psono/data/postgresql:/var/lib/postgresql/data

  psono-server:
    container_name: ${PSONO_DOCKER_PREFIX}-psono-server
    restart: "always"
    image: "psono/psono-server-enterprise:latest"
    depends_on:
      - postgres
    links:
      - postgres:${PSONO_DOCKER_PREFIX}-psono-postgres
    command: sh -c "sleep 10 && python3 psono/manage.py migrate && python3 psono/manage.py createuser admin@${PSONO_USERDOMAIN} admin admin@example.com && python3 psono/manage.py promoteuser admin@${PSONO_USERDOMAIN} superuser && python3 psono/manage.py createuser demo1@${PSONO_USERDOMAIN} demo1 demo1@example.com && python3 psono/manage.py createuser demo2@${PSONO_USERDOMAIN} demo2 demo2@example.com && /bin/sh /root/configs/docker/cmd.sh"
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
    volumes:
      - $INSTALL_DIR/psono/config/settings.yaml:/root/.psono_server/settings.yaml

  psono-fileserver:
    container_name: ${PSONO_DOCKER_PREFIX}-psono-fileserver
    restart: "always"
    image: "psono/psono-fileserver:latest"
    depends_on:
      - psono-server
    links:
      - psono-server:${PSONO_DOCKER_PREFIX}-psono-server
    command: sh -c "sleep 10 && /bin/sh /root/configs/docker/cmd.sh"
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
    volumes:
      - $INSTALL_DIR/psono/data/shard:/opt/psono-shard
      - $INSTALL_DIR/psono/config/settings-fileserver.yaml:$INSTALL_DIR/.psono_fileserver/settings.yaml

  psono-client:
    container_name: ${PSONO_DOCKER_PREFIX}-psono-client
    restart: "always"
    image: "psono/psono-client:latest"
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
    volumes:
      - $INSTALL_DIR/psono/config/config.json:/usr/share/nginx/html/config.json

  psono-admin-client:
    container_name: ${PSONO_DOCKER_PREFIX}-psono-admin-client
    restart: "always"
    image: "psono/psono-admin-client:latest"
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
    volumes:
      - $INSTALL_DIR/psono/config/config.json:/usr/share/nginx/html/portal/config.json

  psono-watchtower:
    container_name: ${PSONO_DOCKER_PREFIX}-psono-watchtower
    restart: "always"
    image: "containrrr/watchtower"
    command: --label-enable --cleanup --interval 3600
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock

EOF

    echo "Crafting docker compose file ... finished"
}

# Other functions remain unchanged...

# Main function to orchestrate the script
main() {
  detect_os
  install_base_dependencies
  install_docker_if_not_exists
  install_docker_compose_if_not_exists
  set_install_dir
  ask_parameters
  craft_docker_compose_file
  stop_container_if_running
  test_if_ports_are_free

  for dir in html postgresql mail shard; do
    mkdir -p $INSTALL_DIR/psono/$dir
  done

  if [ "$PSONO_VERSION" == "DEV" ]; then
    install_git

    echo "Checkout psono-server git repository"
    if [ ! -d "$INSTALL_DIR/psono/psono-server" ]; then
      git clone https://gitlab.com/psono/psono-server.git $INSTALL_DIR/psono/psono-server
    fi
    echo "Checkout psono-server git repository ... finished"
    echo "Checkout psono-client git repository"
    if [ ! -d "$INSTALL_DIR/psono/psono-client" ]; then
      git clone https://gitlab.com/psono/psono-client.git $INSTALL_DIR/psono/psono-client
    fi
    echo "Checkout psono-client git repository ... finished"
    echo "Checkout psono-fileserver git repository"
    if [ ! -d "$INSTALL_DIR/psono/psono-fileserver" ]; then
      git clone https://gitlab.com/psono/psono-fileserver.git $INSTALL_DIR/psono/psono-fileserver
    fi
    echo "Checkout psono-fileserver git repository ... finished"
  fi

  create_dhparam_if_not_exists
  create_openssl_conf
  create_self_signed_certificate_if_not_exists
  create_config_json
  docker_compose_pull
  create_settings_server_yaml
  create_settings_fileserver_yaml
  configure_psono_proxy
  start_stack
  install_acme
  install_alias

  echo ""
  echo "========================="
  echo "CLIENT URL : https://$PSONO_WEBDOMAIN"
  echo "ADMIN URL : https://$PSONO_WEBDOMAIN/portal/"
  echo ""
  echo "USER1: demo1@$PSONO_USERDOMAIN"
  echo "PASSWORD: demo1"
  echo ""
  echo "USER2: demo2@$PSONO_USERDOMAIN"
  echo "PASS: demo2"
  echo ""
  echo "ADMIN: admin@$PSONO_USERDOMAIN"
  echo "PASS: admin"
  echo "========================="
  echo ""
}

main
