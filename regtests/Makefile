# ExaEpi Regression Test Makefile
# Convenience wrapper around regtest.py

# Default variables
MACHINE ?= current
CASES ?= standard
PYTHON ?= python3

# Detect machine if not specified
.PHONY: help
help:
	@echo "ExaEpi Regression Test Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make baseline [CASES=<cases>] [MACHINE=<machine>]  - Create and run baseline tests"
	@echo "  make test [CASES=<cases>] [MACHINE=<machine>]       - Create and run tests"
	@echo "  make compare [MACHINE=<machine>]                    - Compare test results against baselines"
	@echo "  make clean                                          - Remove test directories"
	@echo "  make clean-baselines                                - Remove baseline directories"
	@echo "  make clean-all                                      - Remove all generated directories"
	@echo "  make list-cases                                     - List available test cases"
	@echo "  make list-machines                                  - List available machines"
	@echo "  make validate                                       - Validate environment setup"
	@echo ""
	@echo "Examples:"
	@echo "  make baseline CASES=ca,bay MACHINE=perlmutter"
	@echo "  make test CASES=all"
	@echo "  make compare"
	@echo ""
	@echo "Common test case groups:"
	@echo "  standard    - ca, bay, ma, nm"
	@echo "  all_ca      - All California variants"
	@echo "  quick       - bay, ma"
	@echo "  full        - All test cases"
	@echo ""

.PHONY: validate
validate:
	@$(PYTHON) regtest.py validate

.PHONY: list-cases
list-cases:
	@$(PYTHON) regtest.py list-cases

.PHONY: list-machines
list-machines:
	@$(PYTHON) regtest.py list-machines

.PHONY: create-baseline
create-baseline:
	@$(PYTHON) regtest.py create-baseline --cases $(CASES) --machine $(MACHINE)

.PHONY: run-baseline
run-baseline:
	@$(PYTHON) regtest.py run-baseline --cases $(CASES) --machine $(MACHINE)

.PHONY: baseline
baseline: create-baseline run-baseline
	@echo ""
	@echo "Baseline tests created and launched."
	@echo "Monitor job status with 'squeue' or check baselines/ directory for logs."

.PHONY: create-test
create-test:
	@$(PYTHON) regtest.py create-test --cases $(CASES) --machine $(MACHINE)

.PHONY: run-test
run-test:
	@$(PYTHON) regtest.py run-test --cases $(CASES) --machine $(MACHINE)

.PHONY: test
test: create-test run-test
	@echo ""
	@echo "Tests created and launched."
	@echo "Monitor job status with 'squeue' or check tests/ directory for logs."

.PHONY: compare
compare:
	@$(PYTHON) regtest.py compare --machine $(MACHINE)

.PHONY: clean
clean:
	@echo "Removing tests/ directory..."
	@rm -rf tests/

.PHONY: clean-baselines
clean-baselines:
	@echo "Removing baselines/ directory..."
	@rm -rf baselines/

.PHONY: clean-all
clean-all: clean clean-baselines
	@echo "All test directories removed."

# Full workflow targets
.PHONY: full-baseline
full-baseline:
	@$(MAKE) baseline CASES=full

.PHONY: full-test
full-test:
	@$(MAKE) test CASES=full

.PHONY: quick-test
quick-test:
	@$(MAKE) test CASES=quick

# Useful shortcuts
.PHONY: ca bay ma nm
ca:
	@$(MAKE) test CASES=ca

bay:
	@$(MAKE) test CASES=bay

ma:
	@$(MAKE) test CASES=ma

nm:
	@$(MAKE) test CASES=nm
