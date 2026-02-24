#!/bin/bash
# Gerenciador de Bloqueio do Sistema PACS
# Versão: 2.0.0 - Detecção automática de Tomcat

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_color() { 
    echo -e "${2}${1}${NC}"
}

# Função para detectar versão do Tomcat
detect_tomcat() {
    # Possíveis localizações do Tomcat
    TOMCAT_VERSIONS=("tomcat10" "tomcat9" "tomcat8" "tomcat")
    TOMCAT_HOME=""
    TOMCAT_SERVICE=""
    
    for version in "${TOMCAT_VERSIONS[@]}"; do
        if [ -d "/var/lib/$version" ]; then
            TOMCAT_HOME="/var/lib/$version"
            TOMCAT_SERVICE="$version"
            break
        elif [ -d "/usr/share/$version" ]; then
            TOMCAT_HOME="/usr/share/$version"
            TOMCAT_SERVICE="$version"
            break
        fi
    done
    
    # Se não encontrou, procurar por processo rodando
    if [ -z "$TOMCAT_HOME" ]; then
        TOMCAT_PID=$(pgrep -f "tomcat" | head -1)
        if [ ! -z "$TOMCAT_PID" ]; then
            TOMCAT_HOME=$(ps -ef | grep tomcat | grep -v grep | head -1 | sed -n 's/.*-Dcatalina.base=\([^ ]*\).*/\1/p')
            TOMCAT_SERVICE="tomcat"
        fi
    fi
    
    # Último recurso: procurar em locais comuns
    if [ -z "$TOMCAT_HOME" ]; then
        for dir in /var/lib/tomcat* /usr/share/tomcat* /opt/tomcat*; do
            if [ -d "$dir/webapps" ]; then
                TOMCAT_HOME="$dir"
                TOMCAT_SERVICE=$(basename "$dir")
                break
            fi
        done
    fi
    
    # Verificar se encontrou
    if [ -z "$TOMCAT_HOME" ]; then
        print_color "❌ Tomcat não encontrado!" "$RED"
        return 1
    fi
    
    # Verificar se o serviço está rodando
    if systemctl list-units --full -all | grep -q "$TOMCAT_SERVICE"; then
        TOMCAT_RUNNING="service"
    elif pgrep -f "tomcat" > /dev/null; then
        TOMCAT_RUNNING="process"
    else
        TOMCAT_RUNNING="stopped"
    fi
    
    print_color "✅ Tomcat detectado: $TOMCAT_SERVICE ($TOMCAT_HOME)" "$GREEN"
    return 0
}

# Configurações (serão definidas após detecção)
LAUDUS_DIR=""
INDEX_ORIGINAL=""
INDEX_BLOCK=""
INDEX_CURRENT=""
PACS_SCRIPT="/etc/init.d/pacs.sh"
PACS_BACKUP="/root/pacs.sh"
VERSION="2.0.0"
GIT_REPO="https://raw.githubusercontent.com/celionorajr/pacs-block-system/main"

# Função para configurar caminhos
setup_paths() {
    if detect_tomcat; then
        LAUDUS_DIR="$TOMCAT_HOME/webapps/laudus"
        INDEX_ORIGINAL="$LAUDUS_DIR/index.html.original"
        INDEX_BLOCK="$LAUDUS_DIR/index.html.block"
        INDEX_CURRENT="$LAUDUS_DIR/index.html"
        
        # Criar diretório se não existir
        mkdir -p "$LAUDUS_DIR"
        
        # Ajustar permissões
        chown -R tomcat:tomcat "$LAUDUS_DIR" 2>/dev/null || true
        
        return 0
    else
        return 1
    fi
}

check_tomcat_status() {
    if [ "$TOMCAT_RUNNING" == "service" ]; then
        if systemctl is-active --quiet "$TOMCAT_SERVICE"; then
            echo "Tomcat: ✅ Rodando (serviço $TOMCAT_SERVICE)"
            return 0
        else
            echo "Tomcat: ❌ Parado (serviço $TOMCAT_SERVICE)"
            return 1
        fi
    elif [ "$TOMCAT_RUNNING" == "process" ]; then
        echo "Tomcat: ✅ Rodando (processo)"
        return 0
    else
        echo "Tomcat: ❌ Parado"
        return 1
    fi
}

check_pacs_script() {
    if [ -f "$PACS_SCRIPT" ]; then
        echo "Script PACS: ✅ Em /etc/init.d/"
        return 0
    elif [ -f "$PACS_BACKUP" ]; then
        echo "Script PACS: 📦 Em /root/ (backup)"
        return 1
    else
        echo "Script PACS: ❌ Não encontrado"
        return 2
    fi
}

check_status() {
    echo ""
    print_color "=== STATUS DO SISTEMA PACS v$VERSION ===" "$BLUE"
    echo ""
    
    # Detectar Tomcat
    setup_paths
    
    # Verificar arquivos
    if [ ! -f "$INDEX_BLOCK" ]; then
        print_color "⚠️  Arquivo de bloqueio não encontrado!" "$YELLOW"
    fi
    
    if [ -f "$INDEX_ORIGINAL" ]; then
        print_color "Backup original: ✅ Presente" "$GREEN"
    else
        print_color "Backup original: ⚠️  Não encontrado" "$YELLOW"
    fi
    
    # Verificar página ativa
    if [ -f "$INDEX_CURRENT" ]; then
        if cmp -s "$INDEX_CURRENT" "$INDEX_BLOCK" 2>/dev/null; then
            print_color "Página atual: 🔒 BLOQUEIO ATIVO" "$RED"
        elif [ -f "$INDEX_ORIGINAL" ] && cmp -s "$INDEX_CURRENT" "$INDEX_ORIGINAL" 2>/dev/null; then
            print_color "Página atual: 🟢 SISTEMA LIBERADO" "$GREEN"
        else
            print_color "Página atual: ⚠️  Desconhecida" "$YELLOW"
        fi
    else
        print_color "Página atual: ❌ Não existe" "$RED"
    fi
    
    # Verificar script PACS
    echo ""
    print_color "Script PACS:" "$BLUE"
    check_pacs_script
    
    # Verificar Tomcat
    echo ""
    check_tomcat_status
    
    # Última modificação
    if [ -f "$INDEX_CURRENT" ]; then
        LAST_MOD=$(stat -c "%y" "$INDEX_CURRENT" | cut -d'.' -f1)
        print_color "Última modificação: $LAST_MOD" "$BLUE"
    fi
    
    # Informações do sistema
    echo ""
    print_color "Informações do sistema:" "$BLUE"
    echo "  Tomcat Home: $TOMCAT_HOME"
    echo "  Laudus Dir: $LAUDUS_DIR"
    echo "  Serviço: $TOMCAT_SERVICE"
}

init_system() {
    echo ""
    print_color "=== INICIALIZANDO SISTEMA v$VERSION ===" "$BLUE"
    echo ""
    
    # Detectar Tomcat
    if ! setup_paths; then
        print_color "❌ Erro: Tomcat não encontrado!" "$RED"
        return 1
    fi
    
    # Backup da página atual
    if [ -f "$INDEX_CURRENT" ] && [ ! -f "$INDEX_ORIGINAL" ]; then
        cp "$INDEX_CURRENT" "$INDEX_ORIGINAL"
        print_color "Backup criado: index.html.original" "$GREEN"
    fi
    
    # Verificar página de bloqueio
    if [ ! -f "$INDEX_BLOCK" ]; then
        print_color "Baixando página de bloqueio do GitHub..." "$YELLOW"
        curl -sSL "$GIT_REPO/files/index.html.block" -o "$INDEX_BLOCK"
        if [ $? -eq 0 ] && [ -f "$INDEX_BLOCK" ]; then
            print_color "Página de bloqueio baixada com sucesso!" "$GREEN"
        else
            print_color "ERRO: Falha ao baixar página de bloqueio!" "$RED"
            return 1
        fi
    fi
    
    # Ajustar permissões
    chmod 644 "$INDEX_BLOCK"
    chown -R tomcat:tomcat "$LAUDUS_DIR" 2>/dev/null || true
    
    check_status
    echo ""
    print_color "✅ Sistema inicializado com sucesso!" "$GREEN"
}

activate_block() {
    echo ""
    print_color "=== ATIVANDO BLOQUEIO ===" "$RED"
    echo ""
    
    # Detectar Tomcat
    setup_paths
    
    # Verificar arquivos
    if [ ! -f "$INDEX_BLOCK" ]; then
        print_color "ERRO: Página de bloqueio não encontrada!" "$RED"
        print_color "Execute primeiro: pacs-block init" "$YELLOW"
        return 1
    fi
    
    # Backup do index atual se necessário
    if [ -f "$INDEX_CURRENT" ] && [ ! -f "$INDEX_ORIGINAL" ]; then
        cp "$INDEX_CURRENT" "$INDEX_ORIGINAL"
        print_color "Backup criado: index.html.original" "$GREEN"
    fi
    
    # Mover script PACS
    if [ -f "$PACS_SCRIPT" ]; then
        mv "$PACS_SCRIPT" "$PACS_BACKUP"
        print_color "Script PACS movido para /root/" "$YELLOW"
    fi
    
    # Ativar página de bloqueio
    cp "$INDEX_BLOCK" "$INDEX_CURRENT"
    chmod 644 "$INDEX_CURRENT"
    chown -R tomcat:tomcat "$LAUDUS_DIR" 2>/dev/null || true
    
    print_color "✅ Bloqueio ATIVADO" "$RED"
    
    # Reiniciar Tomcat
    if [ "$TOMCAT_RUNNING" == "service" ]; then
        systemctl restart "$TOMCAT_SERVICE" 2>/dev/null && sleep 3
    elif [ "$TOMCAT_RUNNING" == "process" ]; then
        pkill -f tomcat
        sleep 2
        if [ -f "$TOMCAT_HOME/bin/startup.sh" ]; then
            "$TOMCAT_HOME/bin/startup.sh"
        fi
    fi
    
    check_status
}

deactivate_block() {
    echo ""
    print_color "=== DESATIVANDO BLOQUEIO ===" "$GREEN"
    echo ""
    
    # Detectar Tomcat
    setup_paths
    
    # Restaurar página original
    if [ -f "$INDEX_ORIGINAL" ]; then
        cp "$INDEX_ORIGINAL" "$INDEX_CURRENT"
        print_color "Página original restaurada" "$GREEN"
    else
        print_color "ERRO: Backup original não encontrado!" "$RED"
        return 1
    fi
    
    # Restaurar script PACS
    if [ -f "$PACS_BACKUP" ]; then
        mv "$PACS_BACKUP" "$PACS_SCRIPT"
        print_color "Script PACS restaurado para /etc/init.d/" "$GREEN"
    fi
    
    # Ajustar permissões
    chmod 644 "$INDEX_CURRENT"
    chown -R tomcat:tomcat "$LAUDUS_DIR" 2>/dev/null || true
    
    print_color "✅ Bloqueio DESATIVADO" "$GREEN"
    
    # Reiniciar Tomcat
    if [ "$TOMCAT_RUNNING" == "service" ]; then
        systemctl restart "$TOMCAT_SERVICE" 2>/dev/null && sleep 3
    elif [ "$TOMCAT_RUNNING" == "process" ]; then
        pkill -f tomcat
        sleep 2
        if [ -f "$TOMCAT_HOME/bin/startup.sh" ]; then
            "$TOMCAT_HOME/bin/startup.sh"
        fi
    fi
    
    check_status
}

check_updates() {
    echo ""
    print_color "=== VERIFICANDO ATUALIZAÇÕES ===" "$BLUE"
    echo ""
    
    REMOTE_VERSION=$(curl -sSL "$GIT_REPO/version.txt" 2>/dev/null | head -n1)
    
    if [ -z "$REMOTE_VERSION" ]; then
        print_color "❌ Erro ao verificar atualizações" "$RED"
        return 1
    fi
    
    if [ "$REMOTE_VERSION" != "$VERSION" ]; then
        print_color "📦 Nova versão disponível: $REMOTE_VERSION (atual: $VERSION)" "$YELLOW"
        print_color "Use 'pacs-block update' para atualizar" "$GREEN"
    else
        print_color "✅ Sistema atualizado (versão $VERSION)" "$GREEN"
    fi
}

update_system() {
    echo ""
    print_color "=== ATUALIZANDO SISTEMA ===" "$BLUE"
    echo ""
    
    BACKUP_DIR="/root/pacs-block-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    if [ -f "$INDEX_BLOCK" ]; then
        cp "$INDEX_BLOCK" "$BACKUP_DIR/"
    fi
    if [ -f "/usr/local/bin/manage-block.sh" ]; then
        cp "/usr/local/bin/manage-block.sh" "$BACKUP_DIR/"
    fi
    if [ -f "/usr/local/bin/pacs-block" ]; then
        cp "/usr/local/bin/pacs-block" "$BACKUP_DIR/"
    fi
    
    print_color "Backup criado em: $BACKUP_DIR" "$GREEN"
    print_color "Baixando atualizações..." "$YELLOW"
    
    # Atualizar página de bloqueio
    if [ -d "$LAUDUS_DIR" ]; then
        curl -sSL "$GIT_REPO/files/index.html.block" -o "$INDEX_BLOCK.new"
        if [ $? -eq 0 ]; then
            mv "$INDEX_BLOCK.new" "$INDEX_BLOCK"
            print_color "✅ Página de bloqueio atualizada" "$GREEN"
        fi
    fi
    
    # Atualizar manage-block.sh
    curl -sSL "$GIT_REPO/files/manage-block.sh" -o "/usr/local/bin/manage-block.sh.new"
    if [ $? -eq 0 ]; then
        mv "/usr/local/bin/manage-block.sh.new" "/usr/local/bin/manage-block.sh"
        chmod +x "/usr/local/bin/manage-block.sh"
        print_color "✅ Script principal atualizado" "$GREEN"
    fi
    
    # Atualizar pacs-block
    curl -sSL "$GIT_REPO/files/pacs-block" -o "/usr/local/bin/pacs-block.new"
    if [ $? -eq 0 ]; then
        mv "/usr/local/bin/pacs-block.new" "/usr/local/bin/pacs-block"
        chmod +x "/usr/local/bin/pacs-block"
        print_color "✅ Comando rápido atualizado" "$GREEN"
    fi
    
    print_color "✅ Sistema atualizado com sucesso!" "$GREEN"
}

show_help() {
    echo ""
    print_color "=== GERENCIADOR DE BLOQUEIO PACS v$VERSION ===" "$BLUE"
    echo ""
    print_color "Uso: manage-block.sh [COMANDO]" "$YELLOW"
    echo ""
    echo "Comandos disponíveis:"
    echo "  init          - Inicializar sistema (detecta Tomcat automaticamente)"
    echo "  on            - Ativar bloqueio financeiro"
    echo "  off           - Desativar bloqueio"
    echo "  status        - Verificar status completo do sistema"
    echo "  check-updates - Verificar atualizações disponíveis"
    echo "  update        - Atualizar sistema do GitHub"
    echo "  help          - Mostrar esta ajuda"
    echo ""
    echo "Exemplos:"
    echo "  pacs-block init     # Primeira configuração"
    echo "  pacs-block on       # Bloquear acesso"
    echo "  pacs-block off      # Liberar acesso"
    echo "  pacs-block status   # Ver status"
    echo ""
}

# Menu principal
case "$1" in
    "init")
        init_system
        ;;
    "on"|"bloquear"|"block")
        activate_block
        ;;
    "off"|"desbloquear"|"unblock")
        deactivate_block
        ;;
    "status"|"check")
        check_status
        ;;
    "check-updates")
        check_updates
        ;;
    "update")
        update_system
        ;;
    "help"|"--help"|"-h")
        show_help
        ;;
    *)
        if [ -z "$1" ]; then
            check_status
        else
            print_color "Comando inválido: $1" "$RED"
            show_help
            exit 1
        fi
        ;;
esac

exit 0