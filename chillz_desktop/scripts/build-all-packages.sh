#!/bin/bash
# Master build script for Chillz Desktop Linux packages
# Creates all distribution formats: tarball, AppImage, .deb, .rpm
#
# Usage:
#   ./build-all-packages.sh           # Build all packages
#   ./build-all-packages.sh --quick   # Skip VLC bundling (if already done)
#   ./build-all-packages.sh appimage  # Build only AppImage
#   ./build-all-packages.sh deb       # Build only .deb
#   ./build-all-packages.sh rpm       # Build only .rpm

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

VERSION="1.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  $1"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check dependencies
check_dependencies() {
    print_header "Checking Dependencies"
    
    local missing=()
    
    # Required
    command -v flutter &> /dev/null || missing+=("flutter")
    command -v cmake &> /dev/null || missing+=("cmake")
    command -v gcc &> /dev/null || missing+=("gcc (build-essential)")
    
    # For packages
    command -v dpkg-deb &> /dev/null || print_warning "dpkg-deb not found - .deb creation will fail"
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required dependencies: ${missing[*]}"
        exit 1
    fi
    
    print_success "All required dependencies found"
}

# Build Flutter app
build_flutter() {
    print_header "Building Flutter Application"
    
    # Clean previous build
    print_info "Cleaning previous build..."
    flutter clean 2>/dev/null || true
    
    # Get dependencies
    print_info "Getting dependencies..."
    flutter pub get
    
    # Build release
    print_info "Building release..."
    flutter build linux --release
    
    print_success "Flutter build complete"
}

# Bundle VLC libraries
bundle_vlc() {
    print_header "Bundling VLC Libraries"
    
    if [ -f "$SCRIPT_DIR/create_self_contained_bundle.sh" ]; then
        chmod +x "$SCRIPT_DIR/create_self_contained_bundle.sh"
        "$SCRIPT_DIR/create_self_contained_bundle.sh"
    else
        # Inline bundling
        print_info "Running inline VLC bundling..."
        
        BUILD_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"
        LIB_DIR="$BUILD_DIR/lib"
        VLC_PLUGIN_DIR="$LIB_DIR/vlc/plugins"
        
        mkdir -p "$LIB_DIR"
        mkdir -p "$VLC_PLUGIN_DIR"
        
        # Core VLC
        for lib in libvlc.so libvlccore.so; do
            for search_dir in /usr/lib/x86_64-linux-gnu /usr/lib64 /usr/lib; do
                if [ -f "$search_dir/$lib"* ]; then
                    cp -L "$search_dir/$lib"* "$LIB_DIR/" 2>/dev/null || true
                    break
                fi
            done
        done
        
        # VLC plugins
        for plugin_dir in /usr/lib/x86_64-linux-gnu/vlc/plugins /usr/lib64/vlc/plugins /usr/lib/vlc/plugins; do
            if [ -d "$plugin_dir" ]; then
                cp -rL "$plugin_dir"/* "$VLC_PLUGIN_DIR/" 2>/dev/null || true
                break
            fi
        done
    fi
    
    print_success "VLC bundling complete"
}

# Create packages
create_tarball() {
    print_header "Creating Tarball"
    
    if [ -f "$SCRIPT_DIR/create-linux-package.sh" ]; then
        chmod +x "$SCRIPT_DIR/create-linux-package.sh"
        "$SCRIPT_DIR/create-linux-package.sh"
    else
        mkdir -p "$PROJECT_DIR/dist"
        BUILD_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"
        cd "$(dirname "$BUILD_DIR")"
        tar -czvf "$PROJECT_DIR/dist/Chillz_desktop-$VERSION-linux-x86_64.tar.gz" bundle
    fi
    
    print_success "Tarball created"
}

create_appimage() {
    print_header "Creating AppImage"
    
    if [ -f "$SCRIPT_DIR/create_appimage.sh" ]; then
        chmod +x "$SCRIPT_DIR/create_appimage.sh"
        "$SCRIPT_DIR/create_appimage.sh" || {
            print_warning "AppImage creation failed (FUSE may be required)"
            return 1
        }
    else
        print_warning "create_appimage.sh not found"
        return 1
    fi
    
    print_success "AppImage created"
}

create_deb() {
    print_header "Creating .deb Package"
    
    if [ -f "$SCRIPT_DIR/create_deb.sh" ]; then
        chmod +x "$SCRIPT_DIR/create_deb.sh"
        "$SCRIPT_DIR/create_deb.sh"
    else
        print_warning "create_deb.sh not found"
        return 1
    fi
    
    print_success ".deb package created"
}

create_rpm() {
    print_header "Creating .rpm Package"
    
    if [ -f "$SCRIPT_DIR/create_rpm.sh" ]; then
        chmod +x "$SCRIPT_DIR/create_rpm.sh"
        "$SCRIPT_DIR/create_rpm.sh" || {
            print_warning "RPM creation failed (rpmbuild or fpm required)"
            return 1
        }
    else
        print_warning "create_rpm.sh not found"
        return 1
    fi
    
    print_success ".rpm package created"
}

# Summary
print_summary() {
    print_header "Build Summary"
    
    echo "Packages created in: $PROJECT_DIR/dist/"
    echo ""
    
    if [ -d "$PROJECT_DIR/dist" ]; then
        echo "Available packages:"
        ls -lh "$PROJECT_DIR/dist/"* 2>/dev/null | while read line; do
            echo "  $line"
        done
    fi
    
    echo ""
    echo "Installation instructions:"
    echo ""
    echo "  Tarball:"
    echo "    tar -xzf dist/Chillz_desktop-*.tar.gz"
    echo "    ./bundle/Chillz_desktop"
    echo ""
    echo "  AppImage:"
    echo "    chmod +x dist/Chillz_desktop-*.AppImage"
    echo "    ./dist/Chillz_desktop-*.AppImage"
    echo ""
    echo "  Debian/Ubuntu (.deb):"
    echo "    sudo apt install ./dist/chillz-desktop_*.deb"
    echo ""
    echo "  Fedora/RHEL (.rpm):"
    echo "    sudo dnf install ./dist/chillz-desktop-*.rpm"
}

# Main
main() {
    local skip_vlc=false
    local targets=()
    
    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --quick)
                skip_vlc=true
                ;;
            --skip-vlc)
                skip_vlc=true
                ;;
            appimage|deb|rpm|tarball)
                targets+=("$arg")
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS] [TARGETS]"
                echo ""
                echo "Options:"
                echo "  --quick, --skip-vlc  Skip VLC library bundling"
                echo "  --help, -h           Show this help"
                echo ""
                echo "Targets (if none specified, all are built):"
                echo "  tarball              Create .tar.gz archive"
                echo "  appimage             Create .AppImage"
                echo "  deb                  Create .deb package"
                echo "  rpm                  Create .rpm package"
                exit 0
                ;;
        esac
    done
    
    # Default: build all
    if [ ${#targets[@]} -eq 0 ]; then
        targets=(tarball appimage deb rpm)
    fi
    
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}        CHILLZ DESKTOP LINUX PACKAGE BUILDER           ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}                  Version $VERSION                        ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    
    # Check dependencies
    check_dependencies
    
    # Check if we need to build
    BUILD_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"
    if [ ! -d "$BUILD_DIR" ] || [ ! -f "$BUILD_DIR/Chillz_desktop" ]; then
        build_flutter
        bundle_vlc
    elif [ "$skip_vlc" = false ]; then
        print_info "Build exists. Use --quick to skip rebuilding."
        read -p "Rebuild? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            build_flutter
            bundle_vlc
        fi
    fi
    
    # Create requested packages
    local success=0
    local failed=0
    
    for target in "${targets[@]}"; do
        case "$target" in
            tarball)
                create_tarball && ((success++)) || ((failed++))
                ;;
            appimage)
                create_appimage && ((success++)) || ((failed++))
                ;;
            deb)
                create_deb && ((success++)) || ((failed++))
                ;;
            rpm)
                create_rpm && ((success++)) || ((failed++))
                ;;
        esac
    done
    
    # Print summary
    print_summary
    
    echo ""
    if [ $failed -eq 0 ]; then
        print_success "All $success packages created successfully!"
    else
        print_warning "$success packages succeeded, $failed failed"
    fi
}

main "$@"
