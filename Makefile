PACKAGE         ?= ldb
VERSION         ?= $(shell git describe --tags)
BASE_DIR         = $(shell pwd)
ERLANG_BIN       = $(shell dirname $(shell which erl))
REBAR            = $(shell pwd)/rebar3
MAKE						 = make

.PHONY: test eqc

all: compile

##
## Compilation targets
##

compile:
	$(REBAR) compile

clean: packageclean
	$(REBAR) clean

packageclean:
	rm -fr *.deb
	rm -fr *.tar.gz

##
## Test targets
##

check: test xref dialyzer lint

test: ct eunit

lint:
	${REBAR} as lint lint

eqc:
	${REBAR} as test eqc

eunit:
	${REBAR} as test eunit

ct:
	pkill -9 beam.smp; TRAVIS=true ${REBAR} as test ct

cover:
	pkill -9 beam.smp; TRAVIS=true ${REBAR} as test ct --cover ; \
		${REBAR} cover

shell:
	${REBAR} shell --apps ldb

java-client-test:
	./test/java-client-test

##
## Release targets
##

stage:
	${REBAR} release -d

##
## Evaluation targets
##

basic:
	pkill -9 beam.smp; \
		rm priv/evaluation/logs -rf; \
		rm priv/evaluation/plots -rf; \
		${REBAR} as test ct --readable=false --suite=test/ldb_basic_simulation_SUITE

graph:
	cd priv/evaluation/; \
		ldb_transmission_plot.sh; \
		google-chrome plots/basic/local/multi_mode.pdf

logs:
	  tail -F priv/lager/*/log/*.log

DIALYZER_APPS = kernel stdlib erts sasl eunit syntax_tools compiler crypto

include tools.mk
