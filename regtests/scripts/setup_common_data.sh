#!/bin/bash
#
# Setup common data directory by copying files from EXAEPI_DIR
# This script should be run once on each system (LC, Perlmutter, etc.)
# after cloning the regtests repo
#
# Usage:
#   cd /path/to/regtests
#   ./scripts/setup_common_data.sh
#

set -e

# Check required environment variables
if [ -z "$EXAEPI_DIR" ]; then
    echo "ERROR: EXAEPI_DIR environment variable not set"
    echo "Please set it to your ExaEpi source directory:"
    echo "  export EXAEPI_DIR=/path/to/exaepi"
    exit 1
fi

if [ ! -d "$EXAEPI_DIR" ]; then
    echo "ERROR: EXAEPI_DIR directory does not exist: $EXAEPI_DIR"
    exit 1
fi

# Get script directory and regtests root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGTESTS_ROOT="$(dirname "$SCRIPT_DIR")"
COMMON_DIR="${REGTESTS_ROOT}/common"

echo "=================================================="
echo "ExaEpi Regression Tests - Common Data Setup"
echo "=================================================="
echo ""
echo "EXAEPI_DIR:  $EXAEPI_DIR"
echo "Common dir:  $COMMON_DIR"
echo ""

# Create common directory if it doesn't exist
mkdir -p "$COMMON_DIR"

# Track what we copy
copied_count=0

# Copy census data files
echo "[1/4] Copying census data files..."
if [ -d "$EXAEPI_DIR/data/CensusData" ]; then
    for file in "$EXAEPI_DIR/data/CensusData"/*.{dat,bin}; do
        if [ -f "$file" ]; then
            cp -v "$file" "$COMMON_DIR/"
            ((copied_count++))
        fi
    done
else
    echo "  WARNING: $EXAEPI_DIR/data/CensusData not found"
fi

# Copy case data files
echo ""
echo "[2/4] Copying case data files..."
if [ -d "$EXAEPI_DIR/data/CaseData" ]; then
    for file in "$EXAEPI_DIR/data/CaseData"/*.cases; do
        if [ -f "$file" ]; then
            cp -v "$file" "$COMMON_DIR/"
            ((copied_count++))
        fi
    done
else
    echo "  WARNING: $EXAEPI_DIR/data/CaseData not found"
fi

# Copy input files from examples
echo ""
echo "[3/4] Copying input files..."
if [ -d "$EXAEPI_DIR/examples" ]; then
    for file in "$EXAEPI_DIR/examples"/inputs*; do
        if [ -f "$file" ]; then
            cp -v "$file" "$COMMON_DIR/"
            ((copied_count++))
        fi
    done
else
    echo "  WARNING: $EXAEPI_DIR/examples not found"
fi

# Copy air traffic data
echo ""
echo "[4/4] Copying air traffic data..."
if [ -f "$EXAEPI_DIR/data/CA_CY23AirTraffic.dat" ]; then
    cp -v "$EXAEPI_DIR/data/CA_CY23AirTraffic.dat" "$COMMON_DIR/"
    ((copied_count++))
fi

# Handle urbanpop data - create symlinks if EXAEPI_URBANPOP_DATA is set
echo ""
echo "Setting up urbanpop data files..."
if [ -n "$EXAEPI_URBANPOP_DATA" ]; then
    if [ -d "$EXAEPI_URBANPOP_DATA" ]; then
        echo "  Using EXAEPI_URBANPOP_DATA: $EXAEPI_URBANPOP_DATA"
        for file in "$EXAEPI_URBANPOP_DATA"/urbanpop_*.bin; do
            if [ -f "$file" ]; then
                filename=$(basename "$file")
                ln -sfv "$file" "$COMMON_DIR/$filename"
                ((copied_count++))
            fi
        done
    else
        echo "  WARNING: EXAEPI_URBANPOP_DATA is set but directory doesn't exist: $EXAEPI_URBANPOP_DATA"
    fi
else
    echo "  EXAEPI_URBANPOP_DATA not set - urbanpop tests will not work"
    echo "  Set it to enable urbanpop tests:"
    echo "    export EXAEPI_URBANPOP_DATA=/path/to/urbanpop/data"
fi

echo ""
echo "=================================================="
echo "Setup complete! Copied/linked $copied_count files."
echo "=================================================="
echo ""
echo "Files in common directory:"
ls -lh "$COMMON_DIR" | tail -n +2
echo ""
echo "Total files: $(ls -1 "$COMMON_DIR" | wc -l)"
