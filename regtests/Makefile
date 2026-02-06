# ExaEpi Regression Test Makefile
# Convenience wrapper around regtest.py

# Default variables
# MACHINE: auto-detected (falls back to 'linux' on standard Linux PCs)
# CASES: uses machine-specific defaults (linux defaults to 'quick' = bay, ma)
MACHINE ?=
CASES ?=
PYTHON ?= python3

# Build command line arguments conditionally
MACHINE_ARG = $(if $(MACHINE),--machine $(MACHINE),)
CASES_ARG = $(if $(CASES),--cases $(CASES),)

.PHONY: help
help:
	@echo "ExaEpi Regression Test Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make baseline [CASES=<cases>] [MACHINE=<machine>]  - Create and run baseline tests"
	@echo "  make test [CASES=<cases>] [MACHINE=<machine>]       - Create and run tests"
	@echo "  make compare [MACHINE=<machine>]                    - Compare test results against baselines"
	@echo "  make plot [CASES=<cases>] [MACHINE=<machine>]       - Generate comparison plots"
	@echo "  make clean                                          - Remove test directories"
	@echo "  make clean-baselines                                - Remove baseline directories"
	@echo "  make clean-all                                      - Remove all generated directories"
	@echo "  make list-cases                                     - List available test cases"
	@echo "  make list-machines                                  - List available machines"
	@echo "  make validate                                       - Validate environment setup"
	@echo ""
	@echo "Machines:"
	@echo "  HPC systems (auto-detected): perlmutter, dane, matrix, tuolumne"
	@echo "  Linux PC (auto-fallback):    linux (4 MPI ranks, no GPU)"
	@echo ""
	@echo "  On Linux PCs, CASES defaults to 'quick' (bay, ma tests only)."
	@echo "  Override with CASES=standard to run all tests."
	@echo ""
	@echo "Examples:"
	@echo "  make baseline                          # Auto-detect machine, use defaults"
	@echo "  make baseline CASES=ca,bay MACHINE=perlmutter"
	@echo "  make test CASES=standard               # Run all standard tests"
	@echo "  make compare"
	@echo ""
	@echo "Common test case groups:"
	@echo "  standard    - ca, bay, ma, nm"
	@echo "  all_ca      - All California variants"
	@echo "  quick       - bay, ma (default on linux)"
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
	@$(PYTHON) regtest.py create-baseline $(CASES_ARG) $(MACHINE_ARG)

.PHONY: run-baseline
run-baseline:
	@$(PYTHON) regtest.py run-baseline $(CASES_ARG) $(MACHINE_ARG)

.PHONY: baseline
baseline: create-baseline run-baseline
	@echo ""
	@echo "Baseline tests created and launched."
	@echo "Check baselines/ directory for output logs (out.*.log, run.log)."

.PHONY: create-test
create-test:
	@$(PYTHON) regtest.py create-test $(CASES_ARG) $(MACHINE_ARG)

.PHONY: run-test
run-test:
	@$(PYTHON) regtest.py run-test $(CASES_ARG) $(MACHINE_ARG)

.PHONY: test
test: create-test run-test
	@echo ""
	@echo "Tests created and launched."
	@echo "Check tests/ directory for output logs (out.*.log, run.log)."

.PHONY: compare
compare:
	@$(PYTHON) regtest.py compare $(MACHINE_ARG)

.PHONY: plot
plot:
	@$(PYTHON) regtest.py plot $(CASES_ARG) $(MACHINE_ARG)

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
