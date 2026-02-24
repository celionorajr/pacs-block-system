#!/bin/bash
# Instalador do PACS Block System

GIT_REPO="https://raw.githubusercontent.com/celionorajr/pacs-block-system/main"  # ← ALTERE AQUI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_color() { echo -e "${2}${1}${NC}"; }

echo ""
print_color "=== INSTALADOR PACS BLOCK SYSTEM ===" "$BLUE"
echo ""

# Verificar se é root
if [ "$EUID" -ne 0 ]; then 
    print_color "❌ Execute como root (sudo)" "$RED"
    exit 1
fi

# Verificar dependências
print_color "Verificando dependências..." "$YELLOW"

# Verificar curl
if ! command -v curl &> /dev/null; then
    print_color "Instalando curl..." "$YELLOW"
    apt-get update && apt-get install -y curl
fi

# Criar diretórios
print_color "Criando diretórios..." "$YELLOW"
mkdir -p /var/lib/tomcat9/webapps/laudus
mkdir -p /usr/local/bin
mkdir -p /etc/systemd/system

# Baixar arquivos
print_color "Baixando arquivos do GitHub..." "$YELLOW"

# Página de bloqueio
curl -sSL "$GIT_REPO/files/index.html.block" -o /var/lib/tomcat9/webapps/laudus/index.html.block

# Script principal
curl -sSL "$GIT_REPO/files/manage-block.sh" -o /usr/local/bin/manage-block.sh
chmod +x /usr/local/bin/manage-block.sh

# Comando rápido
curl -sSL "$GIT_REPO/files/pacs-block" -o /usr/local/bin/pacs-block
chmod +x /usr/local/bin/pacs-block

# Scripts de atualização
curl -sSL "$GIT_REPO/scripts/check-updates.sh" -o /usr/local/bin/check-updates.sh
chmod +x /usr/local/bin/check-updates.sh

curl -sSL "$GIT_REPO/scripts/auto-update.sh" -o /usr/local/bin/auto-update.sh
chmod +x /usr/local/bin/auto-update.sh

# Configurar systemd
curl -sSL "$GIT_REPO/systemd/pacs-block.service" -o /etc/systemd/system/pacs-block.service
curl -sSL "$GIT_REPO/systemd/pacs-block.timer" -o /etc/systemd/system/pacs-block.timer

# Habilitar timer
systemctl daemon-reload
systemctl enable pacs-block.timer
systemctl start pacs-block.timer

# Ajustar permissões
chmod 644 /var/lib/tomcat9/webapps/laudus/index.html.block
chown tomcat:tomcat /var/lib/tomcat9/webapps/laudus/index.html.block 2>/dev/null || true

print_color "✅ Instalação concluída!" "$GREEN"
echo ""
print_color "Próximos passos:" "$BLUE"
echo "  1. Execute: pacs-block init"
echo "  2. Para bloquear: pacs-block on"
echo "  3. Para liberar: pacs-block off"
echo "  4. Status: pacs-block status"
echo ""
print_color "O sistema verificará atualizações automaticamente a cada 6 horas" "$YELLOW"
echo ""