#!/bin/bash

set -e

# GITHUB RELEASE URL SCHEMA for concrete release artifact: https://github.com/<organisation>/<repo>/releases/download/<tag>/<concrete_artifact>
# GITHUB RELEASE URL SCHEMA for latest release artifact: https://github.com/<organisation>/<repo>/releases/latest/download/<concrete_artifact> (takes the release marked as latest)
RELEASE_URL_BASE="https://github.com/eclipse-ankaios/ankaios/releases"
BIN_DESTINATION="/usr/local/bin"
CONFIG_DEST="/etc/ankaios"
FILE_STARTUP_STATE="${CONFIG_DEST}/state.yaml"
INSTALL_TYPE="both"
SERVICE_DEST=/etc/systemd/system
ANK_SERVER_SERVICE="ank-server"
FILE_ANK_SERVER_SERVICE="${SERVICE_DEST}/${ANK_SERVER_SERVICE}.service"
ANK_AGENT_SERVICE="ank-agent"
FILE_ANK_AGENT_SERVICE="${SERVICE_DEST}/${ANK_AGENT_SERVICE}.service"
BASEFILE_ANK_UNINSTALL="ank-uninstall.sh"
DEFAULT_LOG_LEVEL="info"

setup_verify_arch() {
    if [ -z "$ARCH" ]; then
        ARCH=$(uname -m)
    fi
    case $ARCH in
        amd64|x86_64)
            ARCH=amd64;;
        arm64|aarch64)
            ARCH=arm64;;
        *)
            fail "Unsupported architecture '${ARCH}'."
    esac

    if [ -z "$OS_NAME" ]; then
        OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
    fi
    case $OS_NAME in
        linux) ;;
        *)
           fail "Unsupported OS kernel type '${OS_NAME}'"
    esac
}

display_usage() {
    echo -e "Usage: $0 [-v] [-t]"
    echo -e "Install Ankaios on a system."
    echo -e "  -v VERSION: Ankaios specific VERSION to install. Default: latest version."
    echo -e "  -t TARGET: Install systemd unit files for TARGET"
    echo -e "             'server', 'agent', 'none' or 'both' (default)"
}

fail() {
    display_usage >&2
    if [ $# -eq 1 ]; then
        echo -e "$1"
    fi
    exit 1
}

download_release() {
    if ! curl -sfLO "$1"; then
        fail "Error: download failed. No resource under '$1'"
    fi
}

cleanup_routine() {
    if [ -d "${ANKAIOS_TMP_DIR}" ]; then
        rm -rf "${ANKAIOS_TMP_DIR}"
    fi
}

trap cleanup_routine EXIT

# parse script args
while getopts v:t: opt; do
    case $opt in
        v) ANKAIOS_VERSION="$OPTARG";;
        t) INSTALL_TYPE="$OPTARG";;
        *)
            fail "Error: Invalid parameter, aborting"
        ;;
    esac
done

# Fail if installation dir does not exist
if [ ! -d "${BIN_DESTINATION}" ]; then
    fail "Error: installation path '${BIN_DESTINATION}' does not exist."
fi

setup_verify_arch
SUFFIX="${OS_NAME}-${ARCH}"
echo "Platform: $SUFFIX"

RELEASE_FILE_NAME="ankaios-${SUFFIX}.tar.gz"
RELEASE_FILE_NAME_WITH_SHA="${RELEASE_FILE_NAME}.sha512sum.txt"

echo "Ankaios version: ${ANKAIOS_VERSION}"

# In case of missing version, download latest
if [ -z "$ANKAIOS_VERSION" ] ; then
    echo "No version provided, use default: latest"
    ANKAIOS_RELEASE_URL="${RELEASE_URL_BASE}/latest/download/${RELEASE_FILE_NAME}"
    ANKAIOS_RELEASE_URL_SHA="${RELEASE_URL_BASE}/latest/download/${RELEASE_FILE_NAME_WITH_SHA}"
    ANKAIOS_CONFIGS_URL="${RELEASE_URL_BASE}/latest/download/ankaios_configs.tar.gz"
else
    echo "Version provided, use version '${ANKAIOS_VERSION}'"
    ANKAIOS_RELEASE_URL="${RELEASE_URL_BASE}/download/${ANKAIOS_VERSION}/${RELEASE_FILE_NAME}"
    ANKAIOS_RELEASE_URL_SHA="${RELEASE_URL_BASE}/download/${ANKAIOS_VERSION}/${RELEASE_FILE_NAME_WITH_SHA}"
    ANKAIOS_CONFIGS_URL="${RELEASE_URL_BASE}/download/${ANKAIOS_VERSION}/ankaios_configs.tar.gz"
fi

if [ -z "$INSTALL_ANK_SERVER_RUST_LOG" ] ; then
    echo "No log level for ank-server provided, use default: 'info'"
    INSTALL_ANK_SERVER_RUST_LOG=${DEFAULT_LOG_LEVEL}
else
    echo "Log level for ank-server provided: '${INSTALL_ANK_SERVER_RUST_LOG}'"
fi

if [ -z "$INSTALL_ANK_AGENT_RUST_LOG" ]; then
    echo "No log level for ank-agent provided, use default: 'info'"
    INSTALL_ANK_AGENT_RUST_LOG=${DEFAULT_LOG_LEVEL}
else
    echo "Log level for ank-agent provided: '${INSTALL_ANK_AGENT_RUST_LOG}'"
fi

ANKAIOS_TMP_DIR=$(mktemp -d)
echo "Creating tmp directory for download artifacts: '${ANKAIOS_TMP_DIR}'"
cd "${ANKAIOS_TMP_DIR}"

echo "Downloading the release: '${ANKAIOS_RELEASE_URL}'"
download_release "${ANKAIOS_RELEASE_URL_SHA}"
download_release "${ANKAIOS_RELEASE_URL}"

# Skip checksum validation if sha512sum is not available
if command -v sha512sum >/dev/null; then
    echo "Checking file checksum"
    sha512sum -c "${RELEASE_FILE_NAME_WITH_SHA}"
else
    echo "Warning: 'sha512sum' not installed. Skipping checksum validation."
fi

# Prefix with sudo if install dir is not writeable with current permissions
BIN_SUDO="sudo"
if [ -w "${BIN_DESTINATION}" ]; then
    BIN_SUDO=""
fi

echo "Extracting the binaries into install folder: '${BIN_DESTINATION}'"
${BIN_SUDO} tar -xvzf "${RELEASE_FILE_NAME}" -C "${BIN_DESTINATION}/"

# Install systemd unit files
if [ -d "$SERVICE_DEST" ]; then
    SVC_SUDO="sudo"
    if [ -w "$SERVICE_DEST" ]; then
        SVC_SUDO=""
    fi

    if [[ "$INSTALL_TYPE" == server || "$INSTALL_TYPE" == both ]]; then
        $SVC_SUDO tee "$FILE_ANK_SERVER_SERVICE" >/dev/null << EOF
[Unit]
Description=Ankaios server

[Service]
Environment="RUST_LOG=${INSTALL_ANK_SERVER_RUST_LOG}"
ExecStart=${BIN_DESTINATION}/ank-server

[Install]
WantedBy=default.target
EOF
    echo "Start server with 'sudo systemctl start $ANK_SERVER_SERVICE'"
    fi

    if [[ "$INSTALL_TYPE" == agent || "$INSTALL_TYPE" == both ]]; then
        $SVC_SUDO tee "$FILE_ANK_AGENT_SERVICE" >/dev/null << EOF
[Unit]
Description=Ankaios agent

[Service]
Environment="RUST_LOG=${INSTALL_ANK_AGENT_RUST_LOG}"
ExecStart=${BIN_DESTINATION}/ank-agent

[Install]
WantedBy=default.target
EOF
    echo "Start agent with 'sudo systemctl start $ANK_AGENT_SERVICE'"
    fi

else
    echo "$$SERVICE_DEST not found. Skipping installation of systemd unit files for Ankaios"
fi

# Write sample state startup config
if [[ "$INSTALL_TYPE" == server || "$INSTALL_TYPE" == both ]]; then
    if ! [ -s "$FILE_STARTUP_STATE" ]; then
        $SVC_SUDO mkdir -p "${CONFIG_DEST}"
        $SVC_SUDO tee "$FILE_STARTUP_STATE" >/dev/null << EOF
# Per default no workload is started. Adapt the file according to your needs.
apiVersion: v0.1
workloads:
#   nginx:
#     runtime: podman
#     agent: agent_A
#     restartPolicy: NEVER
#     tags:
#       - key: owner
#         value: Ankaios team
#     runtimeConfig: |
#       image: docker.io/nginx:latest
#       commandOptions: ["-p", "8081:80"]
EOF
        echo "Created sample startup config in $FILE_STARTUP_STATE."
    else
        echo "Skipping creation of sample startup file in $FILE_STARTUP_STATE as one already exists."
    fi
fi

echo "Downloading the configs: '${ANKAIOS_CONFIGS_URL}'"
download_release "${ANKAIOS_CONFIGS_URL}"

# Extract the config files
ANK_CONFIG_FILE_PATH="${HOME}/.config/ankaios/"
CONFIGS_FILE_NAME="ankaios_configs.tar.gz"

echo "Extracting the config files"
mkdir -p "${ANK_CONFIG_FILE_PATH}"
${BIN_SUDO} tar -xvzf "${CONFIGS_FILE_NAME}" -C "${CONFIG_DEST}" ank-server.conf
${BIN_SUDO} tar -xvzf "${CONFIGS_FILE_NAME}" -C "${CONFIG_DEST}" ank-agent.conf
tar -xvzf "${CONFIGS_FILE_NAME}" -C "${ANK_CONFIG_FILE_PATH}" ank.conf


echo "Customization of your Ankaios system (agent name, server address, etc.) can be done by modifying the following files:"
echo "  - ${ANK_CONFIG_FILE_PATH}/ank.conf for the Ankaios CLI"
echo "  - ${CONFIG_DEST}/ank-server.conf for the Ankaios server"
echo "  - ${CONFIG_DEST}/ank-agent.conf for the Ankaios agent"

# Write uninstall script
${BIN_SUDO} tee "${BIN_DESTINATION}/${BASEFILE_ANK_UNINSTALL}" >/dev/null << EOF
#!/bin/bash
[ \$(id -u) -eq 0 ] || exec sudo \$0 \$@

if command -v systemctl >/dev/null; then
    if [ -s "${FILE_ANK_SERVER_SERVICE}" ]; then
        echo "Stopping Ankaios server and removing from systemd"
        systemctl stop "${ANK_SERVER_SERVICE}"
        systemctl disable "${ANK_SERVER_SERVICE}"
        systemctl daemon-reload
    fi
    if [ -s "${FILE_ANK_AGENT_SERVICE}" ]; then
        echo "Stopping Ankaios agent and removing from systemd"
        systemctl stop "${ANK_AGENT_SERVICE}"
        systemctl disable "${ANK_AGENT_SERVICE}"
        systemctl daemon-reload
    fi
fi
rm -f "${FILE_ANK_SERVER_SERVICE}" "${FILE_ANK_AGENT_SERVICE}"

echo "Removing Ankaios binaries"
rm -f "${BIN_DESTINATION}"/ank{,-server,-agent}
echo "Removing this uninstall script"
rm -f "${BIN_DESTINATION}/${BASEFILE_ANK_UNINSTALL}"
EOF
${BIN_SUDO} chmod +x "${BIN_DESTINATION}/${BASEFILE_ANK_UNINSTALL}"
echo "Created uninstall script ${BIN_DESTINATION}/${BASEFILE_ANK_UNINSTALL}."

echo "Installation has finished."
