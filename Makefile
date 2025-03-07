GLUON_BUILD_DIR := gluon-build
GLUON_GIT_URL := https://github.com/freifunk-gluon/gluon.git
GLUON_GIT_REF := v2022.1.x

PATCH_DIR := ./patches
SECRET_KEY_FILE ?= ${HOME}/build/secret-build

GLUON_TARGETS ?= $(shell cat targets | tr '\n' ' ')

GLUON_AUTOUPDATER_BRANCH := stable

#ifneq (,$(shell git describe --exact-match --tags 2>/dev/null))
#	GLUON_AUTOUPDATER_ENABLED := 1
#	GLUON_RELEASE := $(shell git describe --tags 2>/dev/null)
#else
#	GLUON_AUTOUPDATER_ENABLED := 0
#	EXP_FALLBACK = $(shell date '+%Y%m%d')
#	BUILD_NUMBER ?= $(EXP_FALLBACK)
#	GLUON_RELEASE := $(shell git describe --tags)~exp$(BUILD_NUMBER)
#endif

JOBS ?= $(shell cat /proc/cpuinfo | grep processor | wc -l)

GLUON_MAKE := ${MAKE} -j ${JOBS} -C ${GLUON_BUILD_DIR} \
	GLUON_RELEASE=${GLUON_RELEASE} \
	GLUON_AUTOUPDATER_BRANCH=${GLUON_AUTOUPDATER_BRANCH} \
	GLUON_AUTOUPDATER_ENABLED=${GLUON_AUTOUPDATER_ENABLED} \
    --output-sync=target BUILD_LOG=1 V=s

GLUON_MAKE_D := ${MAKE} --debug=vj -C ${GLUON_BUILD_DIR} \
	GLUON_RELEASE=${GLUON_RELEASE} \
	GLUON_AUTOUPDATER_BRANCH=${GLUON_AUTOUPDATER_BRANCH} \
	GLUON_AUTOUPDATER_ENABLED=${GLUON_AUTOUPDATER_ENABLED} \
    --output-sync=target BUILD_LOG=1 V=s

all: info
	${MAKE} manifest

info:
	@echo
	@echo '#########################'
	@echo '# FFGT Firmware build'
	@echo '# Building release ${GLUON_RELEASE} for branch ${GLUON_AUTOUPDATER_BRANCH} on ${JOBS} cores ...'
	@echo

build: gluon-prepare output-clean
	echo 1 >lfdtgtnr
	for target in ${GLUON_TARGETS}; do \
		echo ""Building target $$target""; \
		date +%s >lastbuildstart; \
		${GLUON_MAKE} download all GLUON_TARGET="$$target" 2>&1 > build_$${target}.log ; \
		makeRC=$$? ;\
		./log_status.sh "$$target" $$makeRC ; \
		echo "Done building target $$target with $$makeRC" ; \
	done

manifest: build
	for branch in master tng rawhide experimental testing stable; do \
		${GLUON_MAKE} manifest GLUON_AUTOUPDATER_BRANCH=$$branch;\
	done
	mv -f ${GLUON_BUILD_DIR}/output/* ./output/

sign: manifest
	${GLUON_BUILD_DIR}/contrib/sign.sh ${SECRET_KEY_FILE} output/images/sysupgrade/${GLUON_AUTOUPDATER_BRANCH}.manifest

${GLUON_BUILD_DIR}:
	mkdir -p ${GLUON_BUILD_DIR}

# Note: "|" means "order only", e.g. "do not care about folder timestamps"
# https://www.gnu.org/savannah-checkouts/gnu/make/manual/html_node/Prerequisite-Types.html
${GLUON_BUILD_DIR}/.git: | ${GLUON_BUILD_DIR}
	git init ${GLUON_BUILD_DIR}
	cd ${GLUON_BUILD_DIR} && git remote add origin ${GLUON_GIT_URL}

gluon-update: | ${GLUON_BUILD_DIR}/.git
	cd ${GLUON_BUILD_DIR} && git fetch --tags origin ${GLUON_GIT_REF}
	cd ${GLUON_BUILD_DIR} && git reset --hard FETCH_HEAD
	cd ${GLUON_BUILD_DIR} && git clean -fd

gluon-prepare: gluon-update
	make gluon-patch
	ln -sfT .. ${GLUON_BUILD_DIR}/site
	${GLUON_MAKE_D} update
	cat /dev/null >/tmp/build-${RELEASE}.log
	echo $$(date +%s) > ${GLUON_BUILD_DIR}/openwrt/version.date
	(cd ${GLUON_BUILD_DIR}/openwrt ; git add version.date ; git commit -m "Build with current time.")

gluon-patch:
	scripts/apply_patches.sh ${GLUON_BUILD_DIR} ${PATCH_DIR}

gluon-clean:
	rm -rf ${GLUON_BUILD_DIR}

output-clean:
	mkdir -p output/
	rm -rf output/*

clean: gluon-clean output-clean
