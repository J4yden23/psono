#!/bin/bash

set -e

export PSONO_DOCKER_PREFIX='psono-docker'

# Function to set installation directory
set_install_dir() {
    INSTALL_DIR='/opt'
    export INSTALL_DIR

    echo "Where do you want Psono to be installed..."
    read -p "INSTALL_DIR [default: $INSTALL_DIR]: " INSTALL_DIR_NEW
    if [ "$INSTALL_DIR_NEW" != "" ]; then
        INSTALL_DIR=$INSTALL_DIR_NEW
    fi

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    rm -Rf "$INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX"
    mkdir -p "$INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX"
}

# Function to detect OS
detect_os() {
    echo "Detecting OS..."
    OS=$(grep ^ID= /etc/os-release | cut -d '=' -f2 | sed -e "s/[[:punct:]]\+//g")
    if [ "$OS" != "ubuntu" ] && [ "$OS" != "debian" ] && [ "$OS" != "centos" ] && [ "$OS" != "rhel" ] && [ "$OS" != "fedora" ]; then
        echo "Unsupported OS" >&2
        exit 1
    fi
    echo "Detected OS: $OS"
}

# Function to install base dependencies
install_base_dependencies() {
    echo "Installing dependencies..."
    deps='curl lsof'
    set +e
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt-get update
        for dep in $deps; do 
            which $dep || apt-get install -y $dep
        done
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
        yum check-update
        for dep in $deps; do 
            which $dep || yum install -y $dep
        done
    fi
    set -e
}

# Function to install Docker
install_docker_if_not_exists() {
    echo "Installing Docker..."
    set +e
    which docker
    if [ $? -ne 0 ] || ! docker --version | grep "Docker version"; then
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
    fi
    systemctl start docker
    set -e
}

# Function to install Docker Compose
install_docker_compose_if_not_exists() {
    echo "Installing Docker Compose..."
    export PATH="$PATH:/usr/local/bin"
    set +e
    which docker-compose
    if [ $? -ne 0 ] || ! docker-compose --version | grep "docker-compose version"; then
        curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    fi
    set -e
}

# Function to ask for parameters
ask_parameters() {
    if [ -f "$INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX/.psonoenv" ]; then
        set -o allexport
        source "$INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX/.psonoenv"
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

    echo "What version do you want to install? (EE, CE, or DEV)"
    read -p "PSONO_VERSION [default: $PSONO_VERSION]: " PSONO_VERSION_NEW
    if [ "$PSONO_VERSION_NEW" != "" ]; then
        export PSONO_VERSION=$PSONO_VERSION_NEW
    fi

    if [[ ! $PSONO_VERSION =~ ^(DEV|EE|CE)$ ]]; then
        echo "Unknown PSONO_VERSION: $PSONO_VERSION" >&2
        exit 1
    fi

    # Continue with other parameters...
    read -p "PSONO_EXTERNAL_PORT [default: $PSONO_EXTERNAL_PORT]: " PSONO_EXTERNAL_PORT_NEW
    if [ "$PSONO_EXTERNAL_PORT_NEW" != "" ]; then
        export PSONO_EXTERNAL_PORT=$PSONO_EXTERNAL_PORT_NEW
    fi

    read -p "PSONO_EXTERNAL_PORT_SECURE [default: $PSONO_EXTERNAL_PORT_SECURE]: " PSONO_EXTERNAL_PORT_SECURE_NEW
    if [ "$PSONO_EXTERNAL_PORT_SECURE_NEW" != "" ]; then
        export PSONO_EXTERNAL_PORT_SECURE=$PSONO_EXTERNAL_PORT_SECURE_NEW
    fi

    # Save environment variables
    cat > "$INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX/.psonoenv" <<EOF
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

    cp "$INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX/.psonoenv" "$INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX/.env"
}

# Function to create Docker Compose file
craft_docker_compose_file() {
    echo "Creating Docker Compose file..."
    cat > "$INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX/docker-compose.yml" <<EOF
version: "2"
services:
  postgres:
    container_name: ${PSONO_DOCKER_PREFIX}-psono-postgres
    restart: always
    image: postgres:12-alpine
    environment:
      POSTGRES_USER: "${PSONO_POSTGRES_USER}"
      POSTGRES_PASSWORD: "${PSONO_POSTGRES_PASSWORD}"
    volumes:
      - $INSTALL_DIR/psono/data/postgresql:/var/lib/postgresql/data

  psono-server:
    container_name: ${PSONO_DOCKER_PREFIX}-psono-server
    restart: always
    image: psono/psono-server:latest
    depends_on:
      - postgres
    environment:
      - POSTGRES_HOST=postgres
    volumes:
      - $INSTALL_DIR/psono/config/settings.yaml:/root/.psono_server/settings.yaml

# Add other services here...
EOF
}

# Function to stop running containers
stop_container_if_running() {
    echo "Stopping containers..."
    if [ -d "$INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX" ]; then
        cd "$INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX"
        docker-compose down 2>/dev/null || true
    fi
}

# Function to test ports
test_if_ports_are_free() {
    echo "Testing port availability..."
    if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null ; then
        echo "Port 80 is occupied" >&2
        exit 1
    fi
    if lsof -Pi :443 -sTCP:LISTEN -t >/dev/null ; then
        echo "Port 443 is occupied" >&2
        exit 1
    fi
}

# Function to install Git
install_git() {
    echo "Installing Git..."
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt-get update
        apt-get install -y git
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
        yum install -y git
    fi
}

# Main function
main() {
    detect_os
    set_install_dir
    install_base_dependencies
    install_docker_if_not_exists
    install_docker_compose_if_not_exists
    ask_parameters
    craft_docker_compose_file
    stop_container_if_running
    test_if_ports_are_free

    # Create necessary directories
    for dir in html postgresql mail shard; do
        mkdir -p "$INSTALL_DIR/psono/$dir"
    done

    if [ "$PSONO_VERSION" = "DEV" ]; then
        install_git
        # Clone repositories if needed
        for repo in server client fileserver; do
            if [ ! -d "$INSTALL_DIR/psono/psono-$repo" ]; then
                git clone "https://gitlab.com/psono/psono-$repo.git" "$INSTALL_DIR/psono/psono-$repo"
            fi
        done
    fi

    # Start services
    cd "$INSTALL_DIR/psono/$PSONO_DOCKER_PREFIX"
    docker-compose up -d

    echo "Installation complete!"
    echo "========================="
    echo "CLIENT URL : https://$PSONO_WEBDOMAIN"
    echo "ADMIN URL : https://$PSONO_WEBDOMAIN/portal/"
    echo ""
    echo "USER1: demo1@$PSONO_USERDOMAIN"
    echo "PASSWORD: demo1"
    echo ""
    echo "USER2: demo2@$PSONO_USERDOMAIN"
    echo "PASSWORD: demo2"
    echo ""
    echo "ADMIN: admin@$PSONO_USERDOMAIN"
    echo "PASSWORD: admin"
    echo "========================="
}

# Run the script
main
