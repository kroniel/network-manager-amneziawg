#!/bin/bash
#
# Build and test script for NetworkManager-amneziawg
#
# Автоматически определяет доступные GTK версии и собирает все найденные.
# Поддерживает Ubuntu, Fedora, Arch и другие дистрибутивы.
#
# Usage: ./scripts/build.sh [OPTIONS]
#
# Options:
#   --clean          Очистить директорию сборки перед сборкой
#   --gtk3           Собрать только с GTK3
#   --gtk4           Собрать только с GTK4
#   --minimal        Собрать без редактора (только сервис)
#   --install        Установить после сборки (требует sudo)
#   --test           Запустить тесты после сборки
#   --help           Показать справку
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Default options
CLEAN=0
INSTALL=0
TEST=0
GTK3=""
GTK4=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN=1
            shift
            ;;
        --install)
            INSTALL=1
            shift
            ;;
        --test)
            TEST=1
            shift
            ;;
        --gtk3)
            GTK3=ON
            GTK4=OFF
            shift
            ;;
        --gtk4)
            GTK3=OFF
            GTK4=ON
            shift
            ;;
        --minimal)
            GTK3=OFF
            GTK4=OFF
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --clean          Очистить директорию сборки перед сборкой"
            echo "  --install        Установить после сборки (требует sudo)"
            echo "  --test           Запустить тесты после сборки"
            echo "  --gtk3           Собрать только с GTK3"
            echo "  --gtk4           Собрать только с GTK4"
            echo "  --minimal        Собрать без редактора (только сервис)"
            echo "  --help, -h       Показать справку"
            echo ""
            echo "По умолчанию собираются все найденные GTK версии."
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Usage: $0 [--clean] [--install] [--test] [--gtk3] [--gtk4] [--minimal]"
            exit 1
            ;;
    esac
done

# Функция для определения libdir
detect_libdir() {
    local prefix="${1:-/usr}"
    
    # Проверяем pkg-config для libnm
    local libdir
    libdir=$(pkg-config --variable=libdir libnm 2>/dev/null || echo "")
    
    if [ -n "$libdir" ]; then
        # Извлекаем относительный путь от prefix
        local rel_libdir="${libdir#$prefix/}"
        echo "$rel_libdir"
        return
    fi
    
    # Fallback: определяем по системе
    if [ -d "$prefix/lib64" ] && [ ! -d "$prefix/lib/x86_64-linux-gnu" ]; then
        echo "lib64"
    elif [ -d "$prefix/lib/x86_64-linux-gnu" ]; then
        echo "lib/x86_64-linux-gnu"
    elif [ -d "$prefix/lib/aarch64-linux-gnu" ]; then
        echo "lib/aarch64-linux-gnu"
    else
        echo "lib"
    fi
}

# Функция для проверки доступности GTK
check_gtk() {
    local version="$1"
    local pkg_name="$2"
    local nma_pkg="$3"
    
    if pkg-config --exists "$pkg_name" 2>/dev/null; then
        if pkg-config --exists "$nma_pkg" 2>/dev/null; then
            echo "ON"
        else
            log_warn "$nma_pkg не найден (требуется для редактора)"
            echo "OFF"
        fi
    else
        echo "OFF"
    fi
}

# Определяем доступные GTK версии
log_info "Проверка доступных зависимостей..."

if [ -z "$GTK3" ]; then
    GTK3=$(check_gtk "3" "gtk+-3.0" "libnma")
    if [ "$GTK3" = "ON" ]; then
        log_success "GTK3 найден ($(pkg-config --modversion gtk+-3.0 2>/dev/null))"
    else
        log_warn "GTK3/libnma не найдены"
    fi
fi

if [ -z "$GTK4" ]; then
    GTK4=$(check_gtk "4" "gtk4" "libnma-gtk4")
    if [ "$GTK4" = "ON" ]; then
        log_success "GTK4 найден ($(pkg-config --modversion gtk4 2>/dev/null))"
    else
        log_warn "GTK4/libnma-gtk4 не найдены"
    fi
fi

# Проверяем другие зависимости
log_info "Проверка зависимостей..."

for pkg in glib-2.0 libnm; do
    if pkg-config --exists "$pkg" 2>/dev/null; then
        log_success "$pkg найден ($(pkg-config --modversion $pkg 2>/dev/null))"
    else
        log_error "$pkg не найден! Установите пакет разработки."
        exit 1
    fi
done

# Проверяем glib-compile-resources
if command -v glib-compile-resources &>/dev/null; then
    log_success "glib-compile-resources найден"
else
    log_error "glib-compile-resources не найден! Установите libglib2.0-dev (Ubuntu) или glib2-devel (Fedora)."
    exit 1
fi

# Определяем libdir
LIBDIR=$(detect_libdir "/usr")
log_info "Install libdir: $LIBDIR"

# Очистка
if [ $CLEAN -eq 1 ]; then
    log_info "Очистка директории сборки..."
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Конфигурация
log_info "Конфигурация CMake..."
echo ""
echo "Build configuration:"
echo "  WITH_GTK3: $GTK3"
echo "  WITH_GTK4: $GTK4"
echo "  LIBDIR: $LIBDIR"
echo ""

cmake .. \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR="$LIBDIR" \
    -DWITH_GTK3="$GTK3" \
    -DWITH_GTK4="$GTK4"

# Сборка
log_info "Сборка..."
cmake --build . --parallel "$(nproc)"

# Тесты
if [ $TEST -eq 1 ]; then
    log_info "Запуск тестов..."
    ctest --output-on-failure
fi

# Установка
if [ $INSTALL -eq 1 ]; then
    log_info "Установка..."
    sudo cmake --install .
    log_success "Установка завершена!"
fi

echo ""
log_success "Сборка успешна!"
echo ""
echo "Результаты:"
echo "  Сервис: $BUILD_DIR/nm-amneziawg-service"
if [ "$GTK3" = "ON" ]; then
    echo "  GTK3 редактор: $BUILD_DIR/libnm-vpn-plugin-amneziawg-editor.so"
fi
if [ "$GTK4" = "ON" ]; then
    echo "  GTK4 редактор: $BUILD_DIR/libnm-gtk4-vpn-plugin-amneziawg-editor.so"
fi
echo ""
echo "Установить: sudo cmake --install $BUILD_DIR"
