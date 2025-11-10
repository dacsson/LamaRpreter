# Makefile for Lama Stack Machine

# === Required Variables ===
# LAMA_PATH: Path to the Lama root directory (must be provided)
# LAMAC: Path to the Lama compiler (e.g., LAMAC binary)

# Check if LAMA_PATH is set
ifeq ($(LAMA_PATH),)
$(error LAMA_PATH is required. Use: make LAMA_PATH=/path/to/lama)
endif

ifeq ($(LAMAC),)
$(error LAMAC is required. Use: make LAMAC=/path/to/LAMAC)
endif

# === Directories ===
DUMP_DIR := dump
BUILD_DIR := build
RUNTIME_DIR := $(LAMA_PATH)/runtime
STD_LIB_DIR := $(LAMA_PATH)/stdlib/x64

# === Targets ===

.PHONY: help dump build run clean

help:
	@echo "Usage: make run FILE=<name>.bs"
	@echo "Required env variables: LAMA_PATH=<path-to-lama-src> LAMAC=<path-to-lamac>"
	@echo "  dump FILE=<name>.lama      Compile .lama file to stack machine code (.sm) and move to ./dump/"
	@echo "  build                      Build LamaRpreter with Zig and copy to ./build/"
	@echo "  run FILE=<name>.bs         Run the compiled .bs file with LamaRpreter"
	@echo "  clean                      Remove build and dump directories"

# === 1. dump ===
dump:
	@if [ -z "$(FILE)" ]; then \
        echo "Error: FILE=<name>.lama is required"; \
        exit 1; \
    fi
	@echo "Compiling $(FILE) to stack code..."
	@$(LAMAC) -64 "$(FILE)" -I "$(STD_LIB_DIR)" -runtime "$(RUNTIME_DIR)" -ds
	@# Extract base name without extension
	@BASENAME=$$(basename "$(FILE)" .lama)
	@# Move .sm file to dump folder
	@mkdir -p "$(DUMP_DIR)"
	@mv "$$(basename "$(FILE)" .lama).sm" "$(DUMP_DIR)/" || echo "No .sm file found to move"
	@rm "$$(basename "$(FILE)" .lama).s"
	@rm "$$(basename "$(FILE)" .lama).i"
	@rm "$$(basename "$(FILE)" .lama)"
	@echo "Stack code dumped to $(DUMP_DIR)/$$(basename "$(FILE)" .lama).sm"

hex:
	@if [ -z "$(FILE)" ]; then \
        echo "Error: FILE=<name>.lama is required"; \
        exit 1; \
    fi
	@echo "Compiling $(FILE) to stack code..."
	@$(LAMAC) -64 "$(FILE)" -I "$(STD_LIB_DIR)" -runtime "$(RUNTIME_DIR)" -b
	@BASENAME=$$(basename "$(FILE)" .lama)
	@mkdir -p "$(DUMP_DIR)"
	@mv "$$(basename "$(FILE)" .lama).bc" "$(DUMP_DIR)/" || echo "No .sm file found to move"
	@echo "Bytecode dumped to $(DUMP_DIR)/$$(basename "$(FILE)" .lama).bc"

# === 2. build ===
build:
	@echo "Building LamaRpreter with Zig..."
	@zig build
	@mkdir -p "$(BUILD_DIR)"
	@cp zig-out/bin/LamaRpreter "$(BUILD_DIR)/"
	@echo "LamaRpreter copied to $(BUILD_DIR)/"

# === 3. run ===
run:
	@if [ -z "$(FILE)" ]; then \
        echo "Error: FILE=<name>.bs is required"; \
        exit 1; \
    fi
	@echo "Running LamaRpreter on $(FILE)..."
	@$(BUILD_DIR)/LamaRpreter "$(FILE)"

# === 4. clean ===
clean:
	@echo "Cleaning build and dump directories..."
	@rm -rf "$(BUILD_DIR)"
	@rm -rf "$(DUMP_DIR)"
	@echo "Done."

# === Default target ===
.PHONY: all
all: help
