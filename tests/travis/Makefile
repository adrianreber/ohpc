TARGETS := check_spec rebuild_srpm

all: $(addprefix Dockerfile., $(TARGETS))
.PHONY: all

Dockerfile.%: Dockerfile.hdr Dockerfile.%.tmpl
	cat $^ > $@

clean:
	rm -f $(addprefix Dockerfile., $(TARGETS))
.PHONY: clean
