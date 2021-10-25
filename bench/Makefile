sname = $(@:.jobid=)
sdeps = cat $(filter %.jobid,$^) | sed -e 's/^/:/' | tr -d '\n'
sbatch = sbatch --parsable -e %x-%j.err
safterok = --dependency=afterok`$(sdeps)`

OUTDIR = out

all: startup-report.jobid

init.jobid: Manifest.toml script/init.sh
	$(sbatch) script/init.sh > $@

_startup = \
	$(sbatch) \
	$(safterok) \
	-J $(sname)-$(1)-$(2) \
	-o $(OUTDIR)/$(sname)_JOBID=%j_N=$(1)_T=$(2).csv \
	--nodes=$(1) \
	--ntasks-per-node=$(2) \
	script/startup.sh

startup.jobid: init.jobid script/startup.sh | $(OUTDIR)
	$(call _startup,4,1) > $@
	$(call _startup,4,2) >> $@

startup-report.jobid: startup.jobid script/startup-report.sh
	$(sbatch) $(safterok) script/startup-report.sh > $@

$(OUTDIR):
	mkdir -p $@
