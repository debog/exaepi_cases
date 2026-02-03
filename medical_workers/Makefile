# ExaEpi Medical Workers Parameter Sweep Makefile
# Convenience wrapper for sweeps.py

STUDY ?= recovery
CASE ?= CA
MACHINE ?= current
MAX_PARALLEL ?= 8

.PHONY: help validate list-studies list-machines create run parse-hospital-data status plot clean

help:
	@echo "ExaEpi Medical Workers Parameter Sweep Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make validate                         - Validate environment setup"
	@echo "  make list-studies                     - List available studies"
	@echo "  make list-machines                    - List available machines"
	@echo "  make create STUDY=<name> CASE=<case>  - Create run directories"
	@echo "  make run STUDY=<name> CASE=<case>     - Run parameter sweep"
	@echo "  make parse-hospital-data STUDY=<name> CASE=<case> - Parse hospital data from logs"
	@echo "  make status STUDY=<name> CASE=<case>  - Check completion status"
	@echo "  make plot STUDY=<name> CASE=<case>    - Generate plots"
	@echo "  make clean STUDY=<name>               - Remove run directories"
	@echo ""
	@echo "Variables:"
	@echo "  STUDY        - Study name (recovery, hosp_interactions)"
	@echo "  CASE         - Case name (CA, Bay)"
	@echo "  MACHINE      - Machine name (current=auto-detect)"
	@echo "  MAX_PARALLEL - Max parallel jobs (default: 8)"
	@echo ""
	@echo "Examples:"
	@echo "  make create STUDY=recovery CASE=CA"
	@echo "  make run STUDY=recovery CASE=CA MACHINE=dane"
	@echo "  make status STUDY=hosp_interactions CASE=Bay"
	@echo "  make plot STUDY=recovery CASE=CA"

validate:
	./sweeps.py validate

list-studies:
	./sweeps.py list-studies

list-machines:
	./sweeps.py list-machines

create:
	./sweeps.py create --study $(STUDY) --case $(CASE) --machine $(MACHINE)

run:
	./sweeps.py run --study $(STUDY) --case $(CASE) --machine $(MACHINE) --max-parallel $(MAX_PARALLEL)

parse-hospital-data:
	./sweeps.py parse-hospital-data --study $(STUDY) --case $(CASE) --machine $(MACHINE)

status:
	./sweeps.py status --study $(STUDY) --case $(CASE) --machine $(MACHINE)

plot:
	./sweeps.py plot --study $(STUDY) --case $(CASE) --machine $(MACHINE)

clean:
	@echo "Removing run directories for $(STUDY)..."
	rm -rf $(STUDY)/.run_*
	@echo "Done."

# Study-specific shortcuts
recovery-ca:
	$(MAKE) create STUDY=recovery CASE=CA
	$(MAKE) run STUDY=recovery CASE=CA

recovery-bay:
	$(MAKE) create STUDY=recovery CASE=Bay
	$(MAKE) run STUDY=recovery CASE=Bay

hosp-ca:
	$(MAKE) create STUDY=hosp_interactions CASE=CA
	$(MAKE) run STUDY=hosp_interactions CASE=CA

hosp-bay:
	$(MAKE) create STUDY=hosp_interactions CASE=Bay
	$(MAKE) run STUDY=hosp_interactions CASE=Bay
