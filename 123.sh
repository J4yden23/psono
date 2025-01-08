#!/bin/bash

set -e

export PSONO_DOCKER_PREFIX='psono-docker'

# Function to detect the operating system
detect_os() {
    echo "Start detect OS"
    OS=$(grep ^ID= /etc/os-release | cut -d '=' -f2 | sed -e "s/[[:punct:]]\+//g")
    if [ "$OS" != "ubuntu" ] \
    && [ "$OS" != "debian" ] \
    && [ "$OS" != "centos" ] \
    && [ "$OS" != "rhel" ] \
    && [ "$OS" != "fedora" ]
    then
        echo "Unsupported OS" >&2
        exit 1
    fi

    echo "Detected OS: $OS"
    echo "Start detect OS ... finished"
}

# Function to install base dependencies
install_base_dependencies() {
    echo "Install dependencies (curl and lsof)..."
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
    echo "Install dependencies ... finished"
}

# Function to install Docker
install_docker_if_not_exists() {
    echo "Install docker if it is not already installed"
    set +e
    which docker
    if [ $? -eq 0 ]; then
        docker --version | grep "Docker version" || {
            curl -fsSL https://get.docker.com -o get-docker.sh
            sh get-docker.sh
            rm get-docker.sh
        }
    else
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
    fi
    systemctl start docker
    set -e
    echo "Install docker ... finished"
}

# Function to install Docker Compose
install_docker_compose_if_not_exists() {
    echo "Install docker compose if it is not already installed"
    echo $PATH | grep '/usr/local/bin' || export PATH="$PATH:/usr/local/bin"
    set +e
    which docker-compose
    if [ $? -eq 0 ]; then
        docker-compose --version | grep "docker-compose version" || {
            curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
        }
    else
        curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    fi
    set -e
    echo "Install docker compose ... finished"
}

# Function to set installation directory
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

# Function to ask for parameters
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

    echo "What version do you want to install? (Usually EE. Potential other choices are CE or DEV)"
    read -p "PSONO_VERSION [default: $PSONO_VERSION]: " PSONO_VERSION_NEW
    if [ "$PSONO_VERSION_NEW" != "" ]; then
        export PSONO_VERSION=$PSONO_VERSION_NEW
    fi

    if [[ ! $PSONO_VERSION =~ ^(DEV|EE|CE)$ ]]; then
        echo "unknown PSONO_VERSION: $PSONO_VERSION" >&2
        exit 1
    fi

    # Add other parameter prompts here...
    # (The rest of the ask_parameters function remains the same)
}

# Function to install Git (for DEV version)
install_git() {
    echo "Install git"
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt-get update
        which git || apt-get install -y git
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
        yum check-update
        which git || yum install -y git
    fi
    echo "Install git ... finished"
}

# Function to test if ports are free
test_if_ports_are_free() {
    echo "Test for port availability"
    if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null; then
        echo "Port 80 is occupied" >&2
        exit 1
    fi
    if lsof -Pi :443 -sTCP:LISTEN -t >/dev/null; then
        echo "Port 443 is occupied" >&2
        exit 1
    fi
    echo "Test for port availability ... finished"
}

# Function to create DH parameters
create_dhparam_if_not_exists() {
    echo "Create DH params if they dont exists"
    mkdir -p $INSTALL_DIR/psono/certificates
    if [ ! -f "$INSTALL_DIR/psono/certificates/dhparam.pem" ]; then
        openssl dhparam -dsaparam -out $INSTALL_DIR/psono/certificates/dhparam.pem 2048
    fi
    echo "Create DH params ... finished"
}

# Function to create OpenSSL configuration
create_openssl_conf() {
    echo "Create openssl config"
    mkdir -p $INSTALL_DIR/psono/certificates
    cat > $INSTALL_DIR/psono/certificates/openssl.conf <<EOF
[req]
default_bits       = 2048
default_keyfile    = $INSTALL_DIR/psono/certificates/private.key
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = v3_ca

[req_distinguished_name]
countryName                 = Country Name (2 letter code)
countryName_default         = US
stateOrProvinceName         = State or Province Name (full name)
stateOrProvinceName_default = New York
localityName                = Locality Name (eg, city)
localityName_default        = Rochester
organizationName            = Organization Name (eg, company)
organizationName_default    = Psono
organizationalUnitName      = organizationalunit
organizationalUnitName_default = Development
commonName                  = Common Name (e.g. server FQDN or YOUR name)
commonName_default          = ${PSONO_WEBDOMAIN}
commonName_max              = 64

[req_ext]
subjectAltName = @alt_names

[v3_ca]
subjectAltName = @alt_names

[alt_names]
DNS.1   = ${PSONO_WEBDOMAIN}
EOF
    echo "Create openssl config ... finished"
}

# Function to create self-signed certificate
create_self_signed_certificate_if_not_exists() {
    echo "Create self signed certificate if it does not exist"
    mkdir -p $INSTALL_DIR/psono/certificates
    if [ ! -f "$INSTALL_DIR/psono/certificates/private.key" ]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout $INSTALL_DIR/psono/certificates/private.key \
            -out $INSTALL_DIR/psono/certificates/public.crt \
            -config $INSTALL_DIR/psono/certificates/openssl.conf -batch
    fi
    echo "Create self signed certificate ... finished"
}

# Add other functions here...
# (Include all the remaining functions from your original script)

# Main function
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
        # Clone repositories for DEV version
        if [ ! -d "$INSTALL_DIR/psono/psono-server" ]; then
            git clone https://gitlab.com/psono/psono-server.git $INSTALL_DIR/psono/psono-server
        fi
        if [ ! -d "$INSTALL_DIR/psono/psono-client" ]; then
            git clone https://gitlab.com/psono/psono-client.git $INSTALL_DIR/psono/psono-client
        fi
        if [ ! -d "$INSTALL_DIR/psono/psono-fileserver" ]; then
            git clone https://gitlab.com/psono/psono-fileserver.git $INSTALL_DIR/psono/psono-fileserver
        fi
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
    echo "Installation Complete!"
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
