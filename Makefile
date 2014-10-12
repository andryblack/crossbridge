# ====================================================================================
# CrossBridge Makefile
# ====================================================================================
$?UNAME=$(shell uname -s)
$?SRCROOT=$(PWD)
ESCAPED_SRCROOT=$(shell echo $(SRCROOT) | sed -e 's/[\/&]/\\&/g')
$?SDK=$(PWD)/sdk
$?BUILDROOT=$(PWD)/build
$?WIN_BUILD=$(BUILDROOT)/win
$?MAC_BUILD=$(BUILDROOT)/mac
$?LINUX_BUILD=$(BUILDROOT)/linux

# ====================================================================================
# DEPENDENCIES
# ====================================================================================
# Dependency Core
$?DEPENDENCY_AVMPLUS=avmplus-master
$?DEPENDENCY_BINUTILS=binutils
$?DEPENDENCY_BMAKE=bmake
$?DEPENDENCY_CMAKE=cmake-3.0.0
$?DEPENDENCY_GDB=gdb-7.3
$?DEPENDENCY_LLVM=llvm-2.9
$?DEPENDENCY_LLVM_GCC=llvm-gcc-4.2-2.9
$?DEPENDENCY_MAKE=make-4.0
$?DEPENDENCY_SWIG=swig-3.0.0
# Dependency Testing
$?DEPENDENCY_DEJAGNU=dejagnu-1.5
# Dependency Compression
$?DEPENDENCY_ZLIB=zlib-1.2.5


$?SRC_PACKAGES=$(DEPENDENCY_BMAKE) \
			$(DEPENDENCY_CMAKE) $(DEPENDENCY_DEJAGNU) \
			$(DEPENDENCY_GDB) $(DEPENDENCY_MAKE) \
			$(DEPENDENCY_SWIG) $(DEPENDENCY_AVMPLUS) \
			$(DEPENDENCY_ZLIB)

# ====================================================================================
# HOST PLATFORM OPTIONS
# ====================================================================================
# Windows or OSX or Linux
ifneq (,$(findstring CYGWIN,$(UNAME)))
	$?PLATFORM="cygwin"
	$?RAWPLAT=cygwin
	ifdef NUMBER_OF_PROCESSORS
		$?THREADS=$(NUMBER_OF_PROCESSORS)
	else
		$?THREADS=2
	endif
	$?nativepath=$(shell cygpath -at mixed $(1))
	$?BUILD_TRIPLE=i686-pc-cygwin
	$?NOPIE=
	$?BIN_TRUE=/usr/bin/true
else ifneq (,$(findstring Darwin,$(UNAME)))
	$?PLATFORM="darwin"
	$?RAWPLAT=darwin
	$?THREADS=$(shell sysctl -n hw.ncpu)
	$?nativepath=$(1)
	$?BUILD_TRIPLE=x86_64-apple-darwin10
	$?NOPIE=
	$?BIN_TRUE=/usr/bin/true
else
	$?PLATFORM="linux"
	$?RAWPLAT=linux
	$?THREADS=1
	$?nativepath=$(1)
	$?BUILD_TRIPLE=x86_64-unknown-linux-gnu
	$?NOPIE=
	$?BIN_TRUE=/bin/true
endif

# ====================================================================================
# TARGET PLATFORM OPTIONS
# ====================================================================================
# Windows
ifneq (,$(findstring cygwin,$(PLATFORM)))
	$?CC=gcc
	$?CXX=g++
	$?EXEEXT=.exe
	$?SOEXT=.dll
	$?SDLFLAGS=
	$?TAMARIN_CONFIG_FLAGS=--target=i686-linux
	$?TAMARINLDFLAGS=" -Wl,--stack,16000000"
	$?TAMARINOPTFLAGS=-Wno-unused-function -Wno-unused-local-typedefs -Wno-maybe-uninitialized -Wno-narrowing -Wno-sizeof-pointer-memaccess -Wno-unused-variable -Wno-unused-but-set-variable -Wno-deprecated-declarations 
	$?BUILD=$(WIN_BUILD)
	$?PLATFORM_NAME=win
	$?HOST_TRIPLE=i686-pc-cygwin
endif
# OSX 
ifneq (,$(findstring darwin,$(PLATFORM)))
	$?CC=clang
	$?CXX=clang++
	$?HOST_CFLAGS=-mmacosx-version-min=10.7
	$?EXEEXT=
	$?SOEXT=.dylib
	$?SDLFLAGS=--build=i686-apple-darwin10
	$?TAMARIN_CONFIG_FLAGS=--enable-clang
	$?TAMARINLDFLAGS=" -m32 -arch=i686"
	$?TAMARINOPTFLAGS=-Wno-deprecated-declarations 
	$?BUILD=$(MAC_BUILD)
	$?PLATFORM_NAME=mac
	$?HOST_TRIPLE=x86_64-apple-darwin10
endif
# Linux
ifneq (,$(findstring linux,$(PLATFORM)))
	$?CC=gcc
	$?CXX=g++
	$?EXEEXT=
	$?SOEXT=.so
	$?SDLFLAGS=--build=i686-unknown-linux
	$?TAMARIN_CONFIG_FLAGS=
	$?TAMARINLDFLAGS=" -m32 -arch=i686"
	$?TAMARINOPTFLAGS=-Wno-deprecated-declarations 
	$?BUILD=$(LINUX_BUILD)
	$?PLATFORM_NAME=linux
	$?HOST_TRIPLE=x86_64-unknown-linux
endif

# Cross-Compile Options
$?CYGTRIPLE=i686-pc-cygwin
$?TRIPLE=avm2-unknown-freebsd8
$?HOST_SDK=$(BUILD)/usr
#$?MINGWTRIPLE=i686-mingw32

# ====================================================================================
# GNU Tool-chain and CC Options
# ====================================================================================
# Host Tools
#$?CC_FOR_BUILD=gcc
export CC:=$(CC)
export CXX:=$(CXX)
# linker tool (symbolic force no-dereference)
$?LN=ln -sfn
# sync tool
$?RSYNC=rsync -az --no-p --no-g --chmod=ugo=rwX -l
# archive tool
$?NATIVE_AR=ar
# java tool
$?JAVA=$(call nativepath,$(shell which java))
$?JAVACOPTS=-target 1.7
# python tool
$?PYTHON=$(call nativepath,$(shell which python))
# Target Tools
$?AR=$(SDK)/usr/bin/ar scru -v
$?SDK_CC=$(SDK)/usr/bin/gcc
$?SDK_CXX=$(SDK)/usr/bin/g++
$?SDK_AR=$(SDK)/usr/bin/ar
$?SDK_NM=$(SDK)/usr/bin/nm
$?SDK_CMAKE=$(HOST_SDK)/bin/cmake
$?SDK_MAKE=$(HOST_SDK)/bin/make
# Extra Tool (Used by LLVM test)
$?FPCMP=$(BUILDROOT)/extra/fpcmp$(EXEEXT)
# Common Flags
$?DBGOPTS=
$?LIBHELPEROPTFLAGS=-O3
$?CFLAGS=-O4
$?CXXFLAGS=-O4

# ====================================================================================
# LLVM and Clang options
# ====================================================================================
$?LLVMASSERTIONS=OFF
$?LLVMTESTS=ON
$?LLVMCMAKEOPTS= 
$?LLVMLDFLAGS=
$?LLVMCFLAGS=
$?LLVMCXXFLAGS=
$?LLVMINSTALLPREFIX=$(BUILD)
$?LLVM_ONLYLLC=false
$?LLVMBUILDTYPE=MinSizeRel
$?LLVMTARGETS=AVM2;AVM2Shim;X86;CBackend
$?CLANG=ON

# ====================================================================================
# AIR or Flex SDK options
# ====================================================================================
ifneq "$(wildcard $(AIR_HOME)/lib/compiler.jar)" ""
 $?FLEX_SDK_TYPE=AdobeAIR
 $?FLEX_SDK_HOME=$(AIR_HOME)
 $?FLEX_ASDOC=java -classpath "$(call nativepath,$(AIR_HOME)/lib/legacy/asdoc.jar)" -Dflex.compiler.theme= -Dflexlib=$(call nativepath,$(AIR_HOME)/frameworks) flex2.tools.ASDoc -compiler.fonts.local-fonts-snapshot=
else ifneq "$(wildcard $(FLEX_HOME)/lib/flex-compiler-oem.jar)" ""
 $?FLEX_SDK_TYPE=ApacheFlex
 $?FLEX_SDK_HOME=$(FLEX_HOME)
 $?FLEX_ASDOC=java -classpath "$(call nativepath,$(FLEX_SDK_HOME)/lib/asdoc.jar)" -Dflexlib=$(call nativepath,$(FLEX_SDK_HOME)/frameworks) flex2.tools.ASDoc
else 
 $(error Adobe AIR SDK and Apache Flex SDK are missing - setting the 'AIR_HOME' or 'FLEX_HOME' environment variable is essential to build the CrossBridge SDK)
endif

# ====================================================================================
# Tamarin options
# ====================================================================================
# ASC1 Flags
$?TAMARINCONFIG=CFLAGS=" -m32 -I$(SRCROOT)/avm2_env/misc -I/usr/local/Cellar/apple-gcc42/4.2.1-5666.3/lib/gcc/i686-apple-darwin11/4.2.1/include/ -DVMCFG_ALCHEMY_SDK_BUILD " CXXFLAGS=" -m32 -I$(SRCROOT)/avm2_env/misc -I/usr/local/Cellar/apple-gcc42/4.2.1-5666.3/lib/gcc/i686-apple-darwin11/4.2.1/include/ $(TAMARINOPTFLAGS) -DVMCFG_ALCHEMY_SDK_BUILD " LDFLAGS=$(TAMARINLDFLAGS) $(SRCROOT)/$(DEPENDENCY_AVMPLUS)/configure.py --enable-shell --enable-alchemy-posix $(TAMARIN_CONFIG_FLAGS)
# ASC1 Tool
$?ASC=$(call nativepath,$(SRCROOT)/$(DEPENDENCY_AVMPLUS)/utils/asc.jar)
# ASC2 Tool
# 1. merge the compiled source into a single output file
# 2. emit metadata information into the bytecode
# 3. future abc
# 4. use the AS3 class based object model for greater performance and better error reporting
# 5. turn on 'parallel generation of method bodies' feature for Alchemy
# 6. turn on the inlining of functions
# 7. make the packages in the abc file available for import
$?ASC2=java -jar $(call nativepath,$(SRCROOT)/tools/lib-air/asc2.jar) -merge -md -abcfuture -AS3 -parallel -inline \
		-import $(call nativepath,$(SRCROOT)/$(DEPENDENCY_AVMPLUS)/generated/builtin.abc) \
		-import $(call nativepath,$(SRCROOT)/$(DEPENDENCY_AVMPLUS)/generated/shell_toplevel.abc)
# ASC2 configuration definitions
# 1. as3 source is for asdocs
# 2. as3 source is for distribution
# 3. as3 source is including trace commands
$?ASC2OPTS=-config CONFIG::asdocs=false -config CONFIG::actual=true -config CONFIG::debug=true
# 1. treat undeclared variable and method access as errors
# 2. produce an optimized abc file
# 3. remove dead code when -optimize is set
$?ASC2EXTRAOPTS=-strict -optimize -removedeadcode
# AVMShell link
$?AVMSHELL=$(SDK)/usr/bin/avmshell$(EXEEXT)

# ====================================================================================
# Other options
# ====================================================================================
$?FLASCC_VERSION_MAJOR:=15
$?FLASCC_VERSION_MINOR:=0
$?FLASCC_VERSION_PATCH:=0
$?FLASCC_VERSION_BUILD:=3
$?SDKNAME=CrossBridge_$(FLASCC_VERSION_MAJOR).$(FLASCC_VERSION_MINOR).$(FLASCC_VERSION_PATCH).$(FLASCC_VERSION_BUILD)
BUILD_VER_DEFS"-DFLASCC_VERSION_MAJOR=$(FLASCC_VERSION_MAJOR) -DFLASCC_VERSION_MINOR=$(FLASCC_VERSION_MINOR) -DFLASCC_VERSION_PATCH=$(FLASCC_VERSION_PATCH) -DFLASCC_VERSION_BUILD=$(FLASCC_VERSION_BUILD)"

# ====================================================================================
# BMAKE
# ====================================================================================
#TODO are we done sweeping for asm?
#$?BMAKE=AR='/usr/bin/true ||' GENCAT=/usr/bin/true RANLIB=/usr/bin/true CC="$(SDK)/usr/bin/gcc -emit-llvm"' -DSTRIP_FBSDID -D__asm__\(X...\)="\error" -D__asm\(X...\)="\error"' MAKEFLAGS="" MFLAGS="" $(BUILD)/bmake/bmake -m $(BUILD)/lib/share/mk 
$?BMAKE=AR='/usr/bin/true ||' GENCAT=/usr/bin/true RANLIB=/usr/bin/true CC="$(SDK)/usr/bin/gcc -emit-llvm -DSTRIP_FBSDID" MAKEFLAGS="" MFLAGS="" $(BUILD)/bmake/bmake -m $(BUILD)/lib/share/mk 

# ====================================================================================
# ALL TARGETS
# ====================================================================================


TESTORDER= test_hello_c test_hello_cpp test_pthreads_c_shell test_pthreads_cpp_swf test_posix 
TESTORDER+= test_sjlj test_sjlj_opt test_eh test_eh_opt test_as3interop test_symbols  
#TESTORDER+= gcctests swigtests llvmtests checkasm 

BUILDORDER= abclibs  
BUILDORDER+= avm2-as alctool alcdb
BUILDORDER+= cmake llvm binutils plugins gcc bmake 
BUILDORDER+= csu libc libthr libm libBlocksRuntime
BUILDORDER+= gcclibs as3wig abcflashpp abcstdlibs_more
BUILDORDER+= sdkcleanup tr trd swig genfs gdb dejagnu
BUILDORDER+= finalcleanup
BUILDORDER+= $(TESTORDER)
BUILDORDER+= samples

# All Tests
all_tests: $(TESTORDER)

# All Libs
all_libs:

# All Targets
all:
	@echo "Building $(SDKNAME)"
	@echo "Please be patient, may take a few hours ..."
	@mkdir -p $(BUILD)/logs
	@$(MAKE) diagnostics &> $(BUILD)/logs/diagnostics.txt 2>&1
	@echo "-  install_libs"
	@$(MAKE) install_libs &> $(BUILD)/logs/install_libs.txt 2>&1
	@echo "-  base"
	@$(MAKE) base &> $(BUILD)/logs/base.txt 2>&1
	@echo "-  make"
	@$(MAKE) make &> $(BUILD)/logs/make.txt 2>&1
	@$(SDK_MAKE) -s all_with_local_make

# Macro for Targets with local Make
all_with_local_make:
	@for target in $(BUILDORDER) ; do \
		echo "-  $$target" ; \
		$(MAKE) $$target &> $(BUILD)/logs/$$target.txt 2>&1; \
		mret=$$? ; \
		logs="$$logs $(BUILD)/logs/$$target.txt" ; \
		grep -q "Resource temporarily unavailable" $(BUILD)/logs/$$target.txt ; \
		gret=$$? ; \
		rcount=1 ; \
		while [ $$gret == 0 ] && [ $$rcount -lt 6 ] ; do \
			echo "-  $$target (retry $$rcount)" ; \
			$(MAKE) $$target &> $(BUILD)/logs/$$target.txt 2>&1; \
			mret=$$? ; \
			grep -q "Resource temporarily unavailable" $(BUILD)/logs/$$target.txt ; \
			gret=$$? ; \
			let rcount=rcount+1 ; \
		done ; \
		if [ $$mret -ne 0 ] ; then \
			echo "Failed to build: $$target" ;\
			exit 1 ; \
		fi ; \
	done 

# Print debug information
diagnostics:
	@echo "~~~ $(SDKNAME) ~~~"
	@echo "User: $(UNAME)"
	@echo "Platform: $(PLATFORM)"
	@echo "Build: $(BUILD)"
	@echo "Triple: $(TRIPLE)"
	@echo "Host Triple: $(HOST_TRIPLE)"
	@echo "Build Triple: $(BUILD_TRIPLE)"
	@echo "CC: $(shell $(CC) --version)"
	@echo "CXX: $(shell $(CXX) --version)"
	@echo "FLEX_SDK_TYPE: $(FLEX_SDK_TYPE)"
	@echo "FLEX_SDK_HOME: $(FLEX_SDK_HOME)"

# Development target
all_dev:
	@$(SDK_MAKE) freeglut

# Development target
all_dev51:
	@$(SDK_MAKE) abclibs_compile
	#@cd samples/05_SWC && $(MAKE)
	@$(SDK_MAKE) test_hello_cpp
	@$(SDK_MAKE) test_hello_c

# Clean build outputs
clean:
	@echo "Cleaning ..."
	@rm -rf $(BUILDROOT)
	@rm -rf $(SDK)
	@$(MAKE) -s clean_libs
	@cd samples && $(MAKE) -s clean
	@echo "Done."


%.unpack:
	tar xf packages/$*.tar.gz

$(DEPENDENCY_AVMPLUS).unpack:
	unzip -q -u packages/$(DEPENDENCY_AVMPLUS).zip

%.clean:
	rm -rf $*

%.patch:
	cd $* && patch -p1 < ../patches/$*.patch

# Install packaged dependency libraries
unpack_libs: clean_libs
	# unpack source libs
	@for target in $(SRC_PACKAGES) ; do \
		$(MAKE) $$target.unpack ; \
	done 

patch_libs: unpack_libs
	# apply patches
	@for target in $(SRC_PACKAGES) ; do \
		$(MAKE) $$target.patch ; \
	done 
	# binary patches
	cp ./tools/asc.jar  ./$(DEPENDENCY_AVMPLUS)/utils/asc.jar


prepare_for_patches: clean patches_clean unpack_libs 
	@for target in $(SRC_PACKAGES) ; do \
		mv $$target $$target.orig ; \
	done 

patches_clean:
	@for target in $(SRC_PACKAGES) ; do \
		rm -rf $$target.orig ; \
	done 

patches:
	@for target in $(SRC_PACKAGES) ; do \
		echo "patch -rupN $$target.orig/ $$target/ > patches/$$target.patch" ; \
	done 

install_libs: unpack_libs patch_libs
	@echo "sources ready"
	

# Clear depdendency libraries
clean_libs:
	#clean libs
	@for target in $(SRC_PACKAGES) ; do \
		$(MAKE) $$target.clean; \
	done 

# ====================================================================================
# BASE
# ====================================================================================
# Initialize the build
base:
	mkdir -p $(BUILDROOT)/extra
	mkdir -p $(BUILD)/abclibs
	mkdir -p $(SDK)/usr
	mkdir -p $(SDK)/usr/bin
	mkdir -p $(SDK)/usr/lib
	mkdir -p $(SDK)/usr/lib/bfd-plugins
	mkdir -p $(SDK)/usr/share
	mkdir -p $(SDK)/usr/platform/$(PLATFORM)/libexec/gcc/$(TRIPLE)

	$(LN) ../usr $(SDK)/usr/$(TRIPLE)
	$(LN) $(PLATFORM) $(SDK)/usr/platform/current
	$(LN) ../ $(SDK)/usr/platform/usr
	$(LN) ../../bin $(SDK)/usr/platform/current/bin
	$(LN) ../../lib $(SDK)/usr/platform/current/lib
	$(LN) ../../share $(SDK)/usr/platform/current/share
	$(LN) platform/current/libexec $(SDK)/usr/libexec
	$(LN) ../../../../../lib $(SDK)/usr/platform/current/libexec/gcc/$(TRIPLE)/lib

	cd $(SDK)/usr/platform/current/bin && $(LN) ar$(EXEEXT) avm2-unknown-freebsd8-ar$(EXEEXT)
	cd $(SDK)/usr/platform/current/bin && $(LN) nm$(EXEEXT) avm2-unknown-freebsd8-nm$(EXEEXT)
	cd $(SDK)/usr/platform/current/bin && $(LN) strip$(EXEEXT) avm2-unknown-freebsd8-strip$(EXEEXT)
	cd $(SDK)/usr/platform/current/bin && $(LN) ranlib$(EXEEXT) avm2-unknown-freebsd8-ranlib$(EXEEXT)
	cd $(SDK)/usr/platform/current/bin && $(LN) gcc$(EXEEXT) avm2-unknown-freebsd8-gcc$(EXEEXT)
	cd $(SDK)/usr/platform/current/bin && $(LN) g++$(EXEEXT) avm2-unknown-freebsd8-g++$(EXEEXT)
	cd $(SDK)/usr/platform/current/bin && $(LN) gcc$(EXEEXT) gcc-4.2$(EXEEXT)
	cd $(SDK)/usr/platform/current/bin && $(LN) g++$(EXEEXT) g++-4.2$(EXEEXT)

	$(RSYNC) $(SRCROOT)/tools/utils-py/add-opt-in.py $(SDK)/usr/bin/
	$(RSYNC) $(SRCROOT)/tools/utils-py/projector-dis.py $(SDK)/usr/bin/
	$(RSYNC) $(SRCROOT)/tools/utils-py/swfdink.py $(SDK)/usr/bin/
	$(RSYNC) $(SRCROOT)/tools/utils-py/swf-info.py $(SDK)/usr/bin/

	$(MAKE) builtinabcs
	$(RSYNC) tools/playerglobal/15.0/airglobal.abc $(SDK)/usr/lib/
	$(RSYNC) tools/playerglobal/15.0/airglobal.swc $(SDK)/usr/lib/
	$(RSYNC) tools/playerglobal/15.0/playerglobal.abc $(SDK)/usr/lib/
	$(RSYNC) tools/playerglobal/15.0/playerglobal.swc $(SDK)/usr/lib/
	$(RSYNC) avm2_env/public-api.txt $(SDK)/
	rm -rf $(DEPENDENCY_AVMPLUS)/generated/builtin.abc
	$(RSYNC) tools/playerglobal/15.0/builtin.abc $(DEPENDENCY_AVMPLUS)/generated/
	cp -f $(DEPENDENCY_AVMPLUS)/generated/*.abc $(SDK)/usr/lib/

	$(RSYNC) --exclude '*iconv.h' avm2_env/usr/include/ $(SDK)/usr/include
	$(RSYNC) avm2_env/usr/lib/ $(SDK)/usr/lib
	cd $(BUILD) && $(ASC2) $(call nativepath,$(SRCROOT)/$(DEPENDENCY_AVMPLUS)/utils/swfmake.as) -outdir . -out swfmake
	cd $(BUILD) && $(ASC2) $(call nativepath,$(SRCROOT)/$(DEPENDENCY_AVMPLUS)/utils/projectormake.as) -outdir . -out projectormake
	cd $(BUILD) && $(ASC2) $(call nativepath,$(SRCROOT)/$(DEPENDENCY_AVMPLUS)/utils/abcdump.as) -outdir . -out abcdump

# ====================================================================================
# MAKE
# ====================================================================================
# Assemble GNU Make
make:
	rm -rf $(BUILD)/make
	mkdir -p $(BUILD)/make
	cp -r $(SRCROOT)/$(DEPENDENCY_MAKE)/* $(BUILD)/make/
	cd $(BUILD)/make && CC=$(CC) CXX=$(CXX) CFLAGS=$(HOST_CFLAGS) ./configure --prefix=$(HOST_SDK)  \
                --build=$(BUILD_TRIPLE) --host=$(HOST_TRIPLE) --target=$(TRIPLE) --program-prefix=""
	cd $(BUILD)/make && $(MAKE)
	cd $(BUILD)/make && $(MAKE) install

# ====================================================================================
# CMAKE
# ====================================================================================
# Assemble CMake
cmake:
	rm -rf $(BUILD)/cmake
	rm -rf $(SDK)/usr/cmake_junk
	mkdir -p $(BUILD)/cmake
	mkdir -p $(HOST_SDK)/cmake_junk
	mkdir -p $(HOST_SDK)/share_cmake/$(DEPENDENCY_CMAKE)/
	cp -r $(SRCROOT)/$(DEPENDENCY_CMAKE)/* $(BUILD)/cmake/
	cd $(BUILD)/cmake && CC=$(CC) CXX=$(CXX) CFLAGS=$(HOST_CFLAGS) CXXFLAGS=$(HOST_CFLAGS) ./configure --prefix=$(HOST_SDK) \
		--datadir=$(HOST_SDK)/share_cmake/$(DEPENDENCY_CMAKE) --docdir=$(HOST_SDK)/cmake_junk --mandir=$(HOST_SDK)/cmake_junk --parallel=$(THREADS)
	cd $(BUILD)/cmake && $(MAKE) -j$(THREADS) VERBOSE=1
	cd $(BUILD)/cmake && $(MAKE) install
	#cp -r $(SDK)/usr/share/$(DEPENDENCY_CMAKE) $(SDK)/usr/platform/$(PLATFORM)/share/

# ====================================================================================
# ABCLIBS
# ====================================================================================
# Assemble builtin ABCs
# Use it if Tamarin AS3 code is modified
builtinabcs:
	mkdir -p $(BUILD)/abclibsposix
	cd $(BUILD)/abclibsposix && $(PYTHON) $(SRCROOT)/posix/gensyscalls.py $(SRCROOT)/posix/syscalls.changed
	cat $(BUILD)/abclibsposix/IKernel.as | sed '1,1d' | sed '$$d' > $(SRCROOT)/posix/IKernel.as
	cp $(BUILD)/abclibsposix/IKernel.as $(SRCROOT)/$(DEPENDENCY_AVMPLUS)/shell
	cp $(BUILD)/abclibsposix/ShellPosix.as $(SRCROOT)/$(DEPENDENCY_AVMPLUS)/shell
	cp $(BUILD)/abclibsposix/ShellPosixGlue.cpp $(SRCROOT)/$(DEPENDENCY_AVMPLUS)/shell
	cp $(BUILD)/abclibsposix/ShellPosixGlue.h $(SRCROOT)/$(DEPENDENCY_AVMPLUS)/shell
	cd $(SRCROOT)/$(DEPENDENCY_AVMPLUS)/core && $(PYTHON) ./builtin.py -abcfuture -config CONFIG::VMCFG_FLOAT=false -config CONFIG::VMCFG_ALCHEMY_SDK_BUILD=true -config CONFIG::VMCFG_ALCHEMY_POSIX=true
	cd $(SRCROOT)/$(DEPENDENCY_AVMPLUS)/shell && $(PYTHON) ./shell_toplevel.py -abcfuture -config CONFIG::VMCFG_FLOAT=false -config CONFIG::VMCFG_ALCHEMY_SDK_BUILD=true -config CONFIG::VMCFG_ALCHEMY_POSIX=true
	cp -f $(DEPENDENCY_AVMPLUS)/generated/*.abc $(SDK)/usr/lib/

# Assemble builtin SysCalls
builtinsyscalls:
	$(SDK)/usr/bin/gcc -c print_stat_info.c 
	$(SDK)/usr/bin/llvm-ld -internalize-public-api-file=$(SDK)/public-api.txt \
	print_stat_info.o $(SDK)/usr/lib/crt1_c.o $(SDK)/usr/lib/libgcc.a \
	$(SDK)/usr/lib/libc.a $(SDK)/usr/lib/libm.a -o print_stat_info-linked
	perl $(SRCROOT)/llvm-2.9/lib/Target/AVM2/build.pl $(SDK)/usr print_stat_info-linked.bc \
	$(SRCROOT)/$(DEPENDENCY_AVMPLUS)/utils/asc.jar $(SRCROOT)/llvm-2.9/lib/Target/AVM2 print_stat_info
	$(AVMSHELL) $(BUILD)/swfmake.abc -- -o print_stat_info.swf \
	$(SDK)/usr/lib/C_Run.abc \
	$(SDK)/usr/lib/Exit.abc $(SDK)/usr/lib/LongJmp.abc \
	$(SDK)/usr/lib/CModule.abc print_stat_info.abc $(SDK)/usr/lib/startHack.abc 
	$(AVMSHELL) $(BUILD)/projectormake.abc -- -o print_stat_info $(AVMSHELL) \
	print_stat_info.swf -- -Djitordie
	chmod u+x print_stat_info
	rm print_stat_info-linked print_stat_info-linked.bc* print_stat_info.abc print_stat_info.cpp \
	print_stat_info.h print_stat_info.o print_stat_info.swf

# Assemble ABC library binaries and documentation
abclibs:
	$(MAKE) abclibs_compile
	$(MAKE) abclibs_asdocs && $(MAKE) asdocs_deploy

# Assemble ABC library binaries
abclibs_compile:
	# Cleaning
	mkdir -p $(BUILD)/abclibs
	mkdir -p $(BUILD)/abclibsposix
	#mkdir -p $(SDK)/usr/lib/abcs
	# Generating the Posix interface
	cd $(BUILD)/abclibsposix && $(PYTHON) $(SRCROOT)/posix/gensyscalls.py $(SRCROOT)/posix/syscalls.changed
	# Post-Processing IKernel
	# TODO: Do not print out files in the source folder (VPMedia)
	cat $(BUILD)/abclibsposix/IKernel.as | sed '1,1d' | sed '$$d' > $(SRCROOT)/posix/IKernel.as
	# Rebuild AVMPlus ABCs
	#$(MAKE) builtinabcs
	# Generating DefaultPreloader
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) -import $(call nativepath,$(SDK)/usr/lib/playerglobal.abc) $(call nativepath,$(SRCROOT)/posix/DefaultPreloader.as) -swf com.adobe.flascc.preloader.DefaultPreloader,800,600,60 -outdir . -out DefaultPreloader
	# Generating ABC Libs
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) $(call nativepath,$(SRCROOT)/posix/ELF.as) -outdir . -out ELF
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) $(call nativepath,$(SRCROOT)/posix/Exit.as) -outdir . -out Exit
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) $(call nativepath,$(SRCROOT)/posix/LongJmp.as) -outdir . -out LongJmp
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) -import Exit.abc $(call nativepath,$(SRCROOT)/posix/C_Run.as) -outdir . -out C_Run
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) $(call nativepath,$(SRCROOT)/posix/vfs/ISpecialFile.as) -outdir . -out ISpecialFile
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) $(call nativepath,$(SRCROOT)/posix/vfs/IBackingStore.as) -outdir . -out IBackingStore
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) -import $(call nativepath,$(SDK)/usr/lib/playerglobal.abc) -import IBackingStore.abc $(call nativepath,$(SRCROOT)/posix/vfs/InMemoryBackingStore.as) -outdir . -out InMemoryBackingStore
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) -import $(call nativepath,$(SDK)/usr/lib/playerglobal.abc) -import IBackingStore.abc -import ISpecialFile.abc $(call nativepath,$(SRCROOT)/posix/vfs/IVFS.as) -outdir . -out IVFS
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) -import $(call nativepath,$(SDK)/usr/lib/playerglobal.abc) -import ISpecialFile.abc -import IBackingStore.abc -import IVFS.abc -import InMemoryBackingStore.abc $(call nativepath,$(SRCROOT)/posix/vfs/DefaultVFS.as) -outdir . -out DefaultVFS
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) -import $(call nativepath,$(SDK)/usr/lib/playerglobal.abc) -import ISpecialFile.abc -import IBackingStore.abc -import IVFS.abc -import InMemoryBackingStore.abc $(call nativepath,$(SRCROOT)/posix/vfs/URLLoaderVFS.as) -outdir . -out URLLoaderVFS
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) -import $(call nativepath,$(SDK)/usr/lib/playerglobal.abc) $(call nativepath, `find $(SRCROOT)/posix/vfs/nochump -name "*.as"`) -outdir . -out AlcVFSZip
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) -import Exit.abc -import C_Run.abc -import IBackingStore.abc -import ISpecialFile.abc -import IVFS.abc -import LongJmp.abc $(call nativepath,$(SRCROOT)/posix/CModule.as) -outdir . -out CModule
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) -import IBackingStore.abc -import IVFS.abc -import ISpecialFile.abc -import CModule.abc -import C_Run.abc -import Exit.abc -import ELF.abc $(call nativepath,$(SRCROOT)/posix/AlcDbgHelper.as) -d -outdir . -out AlcDbgHelper
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) -import IBackingStore.abc -import IVFS.abc -import ISpecialFile.abc -import CModule.abc -import $(call nativepath,$(SDK)/usr/lib/playerglobal.abc) $(call nativepath,$(SRCROOT)/posix/BinaryData.as) -outdir . -out BinaryData
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) -import IBackingStore.abc -import IVFS.abc -import ISpecialFile.abc -import CModule.abc -import C_Run.abc -import $(call nativepath,$(SDK)/usr/lib/playerglobal.abc) $(call nativepath,$(SRCROOT)/posix/Console.as) -outdir . -out Console
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) -import IBackingStore.abc -import IVFS.abc -import ISpecialFile.abc -import CModule.abc -import C_Run.abc -import Exit.abc -import ELF.abc $(call nativepath,$(SRCROOT)/posix/startHack.as) -outdir . -out startHack
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) -import IBackingStore.abc -import IVFS.abc -import ISpecialFile.abc -import CModule.abc -import C_Run.abc $(call nativepath,$(SRCROOT)/posix/ShellCreateWorker.as) -outdir . -out ShellCreateWorker
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) -import IBackingStore.abc -import IVFS.abc -import ISpecialFile.abc -import CModule.abc -import C_Run.abc -import Exit.abc -import $(call nativepath,$(SDK)/usr/lib/playerglobal.abc) $(call nativepath,$(SRCROOT)/posix/PlayerCreateWorker.as) -outdir . -out PlayerCreateWorker
	cd $(BUILD)/abclibs && $(ASC2) $(ASC2OPTS) $(ASC2EXTRAOPTS) -import CModule.abc -import C_Run.abc -import Exit.abc -import IBackingStore.abc -import ISpecialFile.abc -import IVFS.abc -import DefaultVFS.abc -import $(call nativepath,$(SDK)/usr/lib/playerglobal.abc) $(call nativepath,$(SRCROOT)/posix/PlayerKernel.as) -outdir . -out PlayerKernel
	cp $(BUILD)/abclibs/*.abc $(SDK)/usr/lib
	cp $(BUILD)/abclibs/*.swf $(SDK)/usr/lib

# Assemble AS3 documentation
abclibs_asdocs:
	rm -rf $(BUILDROOT)/tempdita
	rm -rf $(BUILDROOT)/apidocs
	mkdir -p $(BUILDROOT)
	mkdir -p $(BUILDROOT)/apidocs
	mkdir -p $(BUILDROOT)/apidocs/tempdita
	mkdir -p $(BUILD)/logs
	cd $(BUILDROOT) && $(FLEX_ASDOC) \
				-load-config= \
				-external-library-path=$(call nativepath,$(FLEX_SDK_HOME)/frameworks/libs/player/15.0/playerglobal.swc) \
				-strict=false -define+=CONFIG::asdocs,true -define+=CONFIG::actual,false -define+=CONFIG::debug,false \
				-doc-sources+=$(call nativepath,$(SRCROOT)/posix/vfs) \
				-doc-sources+=$(call nativepath,$(SRCROOT)/posix) \
				-keep-xml=true \
				-exclude-sources+=$(call nativepath,$(SRCROOT)/posix/startHack.as) \
				-exclude-sources+=$(call nativepath,$(SRCROOT)/posix/IKernel.as) \
				-exclude-sources+=$(call nativepath,$(SRCROOT)/posix/vfs/nochump) \
				-package-description-file=$(call nativepath,$(SRCROOT)/test/aspackages.xml) \
				-main-title "CrossBridge API Reference" \
				-window-title "CrossBridge API Reference" \
				-output apidocs
	mv $(BUILDROOT)/apidocs/tempdita $(BUILDROOT)/

# Deploy AS3 documentation
asdocs_deploy:
	rm -rf $(SDK)/usr/share/asdocs
	mkdir -p $(SDK)/usr/share/asdocs
	$(RSYNC) --exclude "*.xslt" --exclude "*.html" --exclude ASDoc_Config.xml --exclude overviews.xml $(BUILDROOT)/tempdita/ $(SDK)/usr/share/asdocs

# ====================================================================================
# BASICTOOLS
# ====================================================================================

# Assemble TBD Tool
avm2-as:
	$(CXX) $(SRCROOT)/avm2_env/misc/SetAlchemySDKLocation.c $(SRCROOT)/tools/as/as.cpp -o $(SDK)/usr/bin/avm2-as$(EXEEXT) $(HOST_CFLAGS)

# Assemble TBD Tool
alctool:
	rm -rf $(BUILD)/alctool
	mkdir -p $(BUILD)/alctool/flascc
	cp -f $(SRCROOT)/tools/lib-air/*.jar $(SDK)/usr/lib/
	cp -f $(SRCROOT)/tools/lib-air/legacy/*.jar $(SDK)/usr/lib/
	cp -f $(SRCROOT)/tools/aet/*.java $(BUILD)/alctool/flascc/.
	cp -f $(SRCROOT)/tools/common/java/flascc/*.java $(BUILD)/alctool/flascc/.
	cd $(BUILD)/alctool && javac flascc/*.java -cp $(call nativepath,$(SRCROOT)/tools/lib-air/compiler.jar)
	cd $(BUILD)/alctool && echo "Main-Class: flascc.AlcTool" > MANIFEST.MF
	cd $(BUILD)/alctool && echo "Class-Path: compiler.jar" >> MANIFEST.MF
	cd $(BUILD)/alctool && jar cmf MANIFEST.MF alctool.jar flascc/*.class
	cp $(BUILD)/alctool/alctool.jar $(SDK)/usr/lib/.

# Assemble Debugger Tool
alcdb:
	rm -rf $(BUILD)/alcdb
	mkdir -p $(BUILD)/alcdb/flascc
	cp -f $(SRCROOT)/tools/alcdb/*.java $(BUILD)/alcdb/flascc/.
	cp -f $(SRCROOT)/tools/common/java/flascc/*.java $(BUILD)/alcdb/flascc/.
	cd $(BUILD)/alcdb && javac flascc/*.java -cp $(call nativepath,$(SRCROOT)/tools/lib-air/legacy/fdb.jar)
	cd $(BUILD)/alcdb && echo "Main-Class: flascc.AlcDB" > MANIFEST.MF
	cd $(BUILD)/alcdb && echo "Class-Path: fdb.jar" >> MANIFEST.MF
	cd $(BUILD)/alcdb && jar cmf MANIFEST.MF alcdb.jar flascc/*.class 
	cp $(BUILD)/alcdb/alcdb.jar $(SDK)/usr/lib/.

# ====================================================================================
# LLVM
# ====================================================================================
# Assemble LLVM Tool-Chain
llvm:
	rm -rf $(BUILD)/llvm-debug
	mkdir -p $(BUILD)/llvm-debug
	cd $(BUILD)/llvm-debug && LDFLAGS="$(LLVMLDFLAGS) $(HOST_CFLAGS)" CFLAGS="$(LLVMCFLAGS) $(HOST_CFLAGS)" CXXFLAGS="$(LLVMCXXFLAGS) $(HOST_CFLAGS)" $(SDK_CMAKE) -G "Unix Makefiles" \
		$(LLVMCMAKEOPTS) -DCMAKE_INSTALL_PREFIX=$(LLVMINSTALLPREFIX)/llvm-install -DCMAKE_BUILD_TYPE=$(LLVMBUILDTYPE) -DLLVM_BUILD_CLANG=$(CLANG) \
		-DLLVM_ENABLE_ASSERTIONS=$(LLVMASSERTIONS) -DLLVM_BUILD_GOLDPLUGIN=ON -DBINUTILS_INCDIR=$(SRCROOT)/$(DEPENDENCY_BINUTILS)/include \
		-DLLVM_TARGETS_TO_BUILD="$(LLVMTARGETS)" -DLLVM_NATIVE_ARCH="avm2" -DLLVM_INCLUDE_TESTS=$(LLVMTESTS) -DLLVM_INCLUDE_EXAMPLES=OFF \
		$(SRCROOT)/$(DEPENDENCY_LLVM) && $(MAKE) -j$(THREADS) && $(MAKE) install
	cp $(LLVMINSTALLPREFIX)/llvm-install/bin/llc$(EXEEXT) $(SDK)/usr/bin/llc$(EXEEXT)
ifeq ($(LLVM_ONLYLLC), false)
	cp $(LLVMINSTALLPREFIX)/llvm-install/bin/llvm-ar$(EXEEXT) $(SDK)/usr/bin/llvm-ar$(EXEEXT)
	cp $(LLVMINSTALLPREFIX)/llvm-install/bin/llvm-as$(EXEEXT) $(SDK)/usr/bin/llvm-as$(EXEEXT)
	cp $(LLVMINSTALLPREFIX)/llvm-install/bin/llvm-diff$(EXEEXT) $(SDK)/usr/bin/llvm-diff$(EXEEXT)
	cp $(LLVMINSTALLPREFIX)/llvm-install/bin/llvm-dis$(EXEEXT) $(SDK)/usr/bin/llvm-dis$(EXEEXT)
	cp $(LLVMINSTALLPREFIX)/llvm-install/bin/llvm-extract$(EXEEXT) $(SDK)/usr/bin/llvm-extract$(EXEEXT)
	cp $(LLVMINSTALLPREFIX)/llvm-install/bin/llvm-ld$(EXEEXT) $(SDK)/usr/bin/llvm-ld$(EXEEXT)
	cp $(LLVMINSTALLPREFIX)/llvm-install/bin/llvm-link$(EXEEXT) $(SDK)/usr/bin/llvm-link$(EXEEXT)
	cp $(LLVMINSTALLPREFIX)/llvm-install/bin/llvm-nm$(EXEEXT) $(SDK)/usr/bin/llvm-nm$(EXEEXT)
	cp $(LLVMINSTALLPREFIX)/llvm-install/bin/llvm-ranlib$(EXEEXT) $(SDK)/usr/bin/llvm-ranlib$(EXEEXT)
	cp $(LLVMINSTALLPREFIX)/llvm-install/bin/opt$(EXEEXT) $(SDK)/usr/bin/opt$(EXEEXT)
	cp $(LLVMINSTALLPREFIX)/llvm-install/lib/LLVMgold.* $(SDK)/usr/lib/LLVMgold$(SOEXT)
	cp -f $(BUILD)/llvm-debug/bin/fpcmp$(EXEEXT) $(BUILDROOT)/extra/fpcmp$(EXEEXT)
endif

# Assemble LLVM Tests
llvmtests:
	rm -rf $(BUILD)/llvm-tests
	mkdir -p $(BUILD)/llvm-tests
	cp -f $(SDK)/usr/bin/avmshell-release-debugger $(SDK)/usr/bin/avmshell
	#cp -f $(BUILD)/llvm-install/llvm-lit $(SDK)/usr/bin/llvm-lit
	cd $(BUILD)/llvm-tests && $(SRCROOT)/$(DEPENDENCY_LLVM)/configure --with-llvmgcc=$(SDK)/usr/bin/gcc --with-llvmgxx=$(SDK)/usr/bin/g++ --without-f2c --without-f95 --disable-clang --enable-jit=no --target=$(TRIPLE) --prefix=$(BUILD)/llvm-install
	cd $(BUILD)/llvm-tests && $(LN) $(SDK)/usr Release
	cd $(BUILD)/llvm-tests/projects/test-suite/MultiSource && (LANG=C && $(MAKE) TEST=nightly TARGET_LLCFLAGS=-jvm="$(JAVA)" -j$(THREADS) FPCMP=$(FPCMP) DISABLE_CBE=1)
	cd $(BUILD)/llvm-tests/projects/test-suite/SingleSource && (LANG=C && $(MAKE) TEST=nightly TARGET_LLCFLAGS=-jvm="$(JAVA)" -j$(THREADS) FPCMP=$(FPCMP) DISABLE_CBE=1)
	$(PYTHON) $(SRCROOT)/tools/llvmtestcheck.py --srcdir $(SRCROOT)/$(DEPENDENCY_LLVM)/projects/test-suite/ --builddir $(BUILD)/llvm-tests/projects/test-suite/ --fpcmp $(FPCMP)> $(BUILD)/llvm-tests/passfail.txt
	cp $(BUILD)/llvm-tests/passfail.txt $(BUILD)/passfail_llvm.txt

# Assemble LLVM SpecCPU2006 Test
llvmtests-speccpu2006: # works only on mac!
	rm -rf $(BUILD)/llvm-tests
	rm -rf $(BUILD)/llvm-spec-tests
	mkdir -p $(BUILD)/llvm-tests
	cp -f $(SDK)/usr/bin/avmshell-release-debugger $(SDK)/usr/bin/avmshell
	mkdir -p $(BUILD)/llvm-externals && cd $(BUILD)/llvm-externals && curl http://alchemy.corp.adobe.com/speccpu2006.tar.bz2 | tar xvjf -
	#mkdir -p $(BUILD)/llvm-externals && cd $(BUILD)/llvm-externals && cat $(SRCROOT)/speccpu2006.tar.bz2 | tar xvjf -
	cd $(BUILD)/llvm-tests && $(SRCROOT)/$(DEPENDENCY_LLVM)/configure --without-f2c --without-f95 --with-llvmgcc=$(SDK)/usr/bin/gcc --with-llvmgxx=$(SDK)/usr/bin/g++ --with-externals=$(BUILD)/llvm-externals --disable-clang --enable-jit=no --target=$(TRIPLE) --prefix=$(BUILD)/llvm-install
	cd $(BUILD)/llvm-tests && $(LN) $(SDK)/usr Release
	cd $(BUILD)/llvm-tests/projects/test-suite/External && (LANG=C && $(MAKE) TEST=nightly TARGET_LLCFLAGS=-jvm="$(JAVA)" -j$(THREADS) FPCMP=$(FPCMP) DISABLE_CBE=1 CXXFLAGS+='-DSPEC_CPU_MACOSX -DSPEC_CPU_NO_HAS_SIGSETJMP' CFLAGS+='-DSPEC_CPU_MACOSX -DSPEC_CPU_NO_HAS_SIGSETJMP')
	$(PYTHON) $(SRCROOT)/tools/llvmtestcheck.py --fpcmp $(FPCMP) --srcdir $(SRCROOT)/$(DEPENDENCY_LLVM)/projects/test-suite/ --builddir $(BUILD)/llvm-tests/projects/test-suite/ > $(BUILD)/llvm-tests/passfail.txt
	cp $(BUILD)/llvm-tests/passfail.txt $(BUILD)/passfail_spec.txt
	cp -r $(BUILD)/llvm-tests/projects $(BUILD)/llvm-spec-tests

# ====================================================================================
# BINUTILS
# ====================================================================================
binutils:
ifneq (,$(findstring cygwin,$(PLATFORM)))
	$(SDK_MAKE) -i binutils_build
else
	$(SDK_MAKE) binutils_build
endif

# Assemble LLVM BinUtils
binutils_build:
	rm -rf $(BUILD)/binutils
	mkdir -p $(BUILD)/binutils
	cd $(BUILD)/binutils && CC=$(CC) CXX=$(CXX) CFLAGS="-I$(SRCROOT)/avm2_env/misc/ $(DBGOPTS) $(HOST_CFLAGS)" CXXFLAGS="-I$(SRCROOT)/avm2_env/misc/ $(DBGOPTS) $(HOST_CFLAGS)" $(SRCROOT)/$(DEPENDENCY_BINUTILS)/configure \
		--disable-doc --disable-nls --enable-gold --disable-ld --enable-plugins \
		--build=$(BUILD_TRIPLE) --host=$(HOST_TRIPLE) --target=$(TRIPLE) --with-sysroot=$(SDK)/usr \
		--program-prefix="" --prefix=$(SDK)/usr --disable-werror \
		--enable-targets=$(TRIPLE)
	cd $(BUILD)/binutils && $(MAKE) -j$(THREADS) && $(MAKE) install
	mv $(SDK)/usr/bin/ld.gold$(EXEEXT) $(SDK)/usr/bin/ld$(EXEEXT)
	rm -rf $(SDK)/usr/bin/readelf$(EXEEXT) $(SDK)/usr/bin/elfedit$(EXEEXT) $(SDK)/usr/bin/ld.bfd$(EXEEXT) $(SDK)/usr/bin/objdump$(EXEEXT) $(SDK)/usr/bin/objcopy$(EXEEXT) $(SDK)/usr/share/info $(SDK)/usr/share/man

# ====================================================================================
# PLUGINS
# ====================================================================================
# Assemble LLVM Plug-ins
plugins:
	rm -rf $(BUILD)/makeswf $(BUILD)/multiplug $(BUILD)/zlib
	mkdir -p $(BUILD)/makeswf $(BUILD)/multiplug $(BUILD)/zlib
	cd $(BUILD)/makeswf && $(CXX) $(DBGOPTS) -I$(SRCROOT)/avm2_env/misc/ -DHAVE_ABCNM -DDEFTMPDIR=\"$(call nativepath,/tmp)\" \
		-DDEFSYSROOT=\"$(call nativepath,$(SDK))\" -DHAVE_STDINT_H -I$(SRCROOT)/$(DEPENDENCY_ZLIB)/ \
		-I$(SRCROOT)/$(DEPENDENCY_BINUTILS)/include -fPIC -c $(SRCROOT)/gold-plugins/makeswf.cpp $(HOST_CFLAGS)
	cd $(BUILD)/makeswf && $(CXX) $(DBGOPTS) -shared -Wl,-headerpad_max_install_names,-undefined,dynamic_lookup \
		-o makeswf$(SOEXT) makeswf.o
	cd $(BUILD)/multiplug && $(CXX) $(DBGOPTS) -I$(SRCROOT)/avm2_env/misc/  \
		-DHAVE_STDINT_H -DSOEXT=\"$(SOEXT)\" -DDEFSYSROOT=\"$(call nativepath,$(SDK))\" \
		-I$(SRCROOT)/$(DEPENDENCY_BINUTILS)/include -fPIC -c $(SRCROOT)/gold-plugins/multiplug.cpp $(HOST_CFLAGS)
	cd $(BUILD)/multiplug && $(CXX) $(DBGOPTS) -shared -Wl,-headerpad_max_install_names,-undefined,dynamic_lookup \
		-o multiplug$(SOEXT) multiplug.o $(HOST_CFLAGS)
	cp -f $(BUILD)/makeswf/makeswf$(SOEXT) $(SDK)/usr/lib/makeswf$(SOEXT)
	cp -f $(BUILD)/multiplug/multiplug$(SOEXT) $(SDK)/usr/lib/multiplug$(SOEXT)
	cp -f $(BUILD)/multiplug/multiplug$(SOEXT) $(SDK)/usr/lib/bfd-plugins/multiplug$(SOEXT)

# ====================================================================================
# GCC
# ====================================================================================
# Assemble LLVM GCC 4.2
gcc:
	rm -rf $(BUILD)/llvm-gcc-42
	mkdir -p $(BUILD)/llvm-gcc-42
	cd $(BUILD)/llvm-gcc-42 && CFLAGS='$(NOPIE) -DSHARED_LIBRARY_EXTENSION=$(SOEXT) $(BUILD_VER_DEFS) -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS -Os $(DBGOPTS) -I$(SRCROOT)/avm2_env/misc/ $(HOST_CFLAGS)' \
		CC=$(CC) CXX=$(CXX) LDFLAGS=$(HOST_CFLAGS) $(SRCROOT)/llvm-gcc-4.2-2.9/configure --enable-languages=c,c++ \
		--enable-llvm=$(LLVMINSTALLPREFIX)/llvm-install/ --disable-bootstrap --disable-multilib --disable-libada --disable-doc --disable-nls \
		--enable-sjlj-exceptions --disable-shared --program-prefix="" \
		--prefix=$(SDK)/usr --with-sysroot="" --with-build-sysroot=$(SDK)/ \
		--build=$(BUILD_TRIPLE) --host=$(HOST_TRIPLE) --target=$(TRIPLE)
	cd $(BUILD)/llvm-gcc-42 && CC=$(CC) CXX=$(CXX)  $(MAKE) -j$(THREADS) all-gcc \
		CFLAGS_FOR_TARGET='$(NOPIE) -DSHARED_LIBRARY_EXTENSION=$(SOEXT) $(BUILD_VER_DEFS) -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS -Os -emit-llvm -I$(SRCROOT)/avm2_env/misc/ ' \
		CXXFLAGS_FOR_TARGET='$(NOPIE) -DSHARED_LIBRARY_EXTENSION=$(SOEXT) $(BUILD_VER_DEFS) -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS -Os -emit-llvm -I$(SRCROOT)/avm2_env/misc/ ' && $(MAKE) install-gcc
	rm -f $(SDK)/usr/bin/gccbug*
	rm -f $(BUILD)/llvm-gcc-42/gcc/gccbug*
	rm -rf $(SDK)/usr/lib/avm2-unknown-freebsd8
	mv $(SDK)/usr/lib/gcc/* $(SDK)/usr/lib/
	mv $(SDK)/usr/lib/avm2-unknown-freebsd8/4.2.1/*.a $(SDK)/usr/lib/
	rmdir $(SDK)/usr/lib/gcc
	$(RSYNC) $(SDK)/usr/libexec/gcc/avm2-unknown-freebsd8/4.2.1/ $(SDK)/usr/bin/
	rm -rf $(SDK)/usr/libexec

# ====================================================================================
# BMAKE
# ====================================================================================
# Assemble BMake
bmake:
	rm -rf $(BUILD)/bmake
	mkdir -p $(BUILD)/bmake
	cd $(BUILD)/bmake && $(SRCROOT)/$(DEPENDENCY_BMAKE)/configure && bash make-bootstrap.sh

# ====================================================================================
# STDLIBS
# ====================================================================================

# TBD
csu:
	$(RSYNC) avm2_env/usr/ $(BUILD)/lib/
	cd $(BUILD)/lib/src/lib/csu/avm2 && $(BMAKE) SSP_CFLAGS="" MACHINE_ARCH=avm2 crt1_c.o
	cp -f $(BUILD)/lib/src/lib/csu/avm2/crt1_c.o $(SDK)/usr/lib/.

# TBD
# TODO: We are already calling gensyscalls.py in abclibs_compile phase, is second time really necessary?! (VPMedia)
libc:
	mkdir -p $(BUILD)/posix/
	rm -f $(BUILD)/posix/*.o
	mkdir -p $(BUILD)/lib/src/lib/libc/
	$(RSYNC) avm2_env/usr/ $(BUILD)/lib/
	cd $(BUILD)/posix && $(PYTHON) $(SRCROOT)/posix/gensyscalls.py $(SRCROOT)/posix/syscalls.changed
	cp $(BUILD)/posix/IKernel.as $(SRCROOT)/$(DEPENDENCY_AVMPLUS)/shell
	cp $(BUILD)/posix/ShellPosix.as $(SRCROOT)/$(DEPENDENCY_AVMPLUS)/shell
	cp $(BUILD)/posix/ShellPosixGlue.cpp $(SRCROOT)/$(DEPENDENCY_AVMPLUS)/shell
	cp $(BUILD)/posix/ShellPosixGlue.h $(SRCROOT)/$(DEPENDENCY_AVMPLUS)/shell
	cd $(SRCROOT)/$(DEPENDENCY_AVMPLUS)/shell && $(PYTHON) ./shell_toplevel.py -config CONFIG::VMCFG_ALCHEMY_POSIX=true
	cd $(BUILD)/posix && $(SDK)/usr/bin/gcc -emit-llvm -fno-stack-protector $(LIBHELPEROPTFLAGS) -c posix.c
	cd $(BUILD)/posix && $(SDK)/usr/bin/gcc -emit-llvm -fno-stack-protector $(LIBHELPEROPTFLAGS) -c $(SRCROOT)/posix/vgl.c
	cd $(BUILD)/posix && $(SDK)/usr/bin/gcc -emit-llvm -fno-stack-protector $(LIBHELPEROPTFLAGS) -D_KERNEL -c $(SRCROOT)/avm2_env/usr/src/kern/kern_umtx.c
	cd $(BUILD)/posix && $(SDK)/usr/bin/gcc -emit-llvm -fno-stack-protector $(LIBHELPEROPTFLAGS) -I $(SRCROOT)/avm2_env/usr/src/lib/libc/include/ -c $(SRCROOT)/posix/thrStubs.c
	cd $(BUILD)/posix && $(SDK)/usr/bin/gcc -emit-llvm -fno-stack-protector $(LIBHELPEROPTFLAGS) -c $(SRCROOT)/posix/kpmalloc.c
	cd $(BUILD)/posix && cp *.o $(BUILD)/lib/src/lib/libc/
	cd $(BUILD)/lib/src/lib/libc && $(BMAKE) -j$(THREADS) SSP_CFLAGS="" MACHINE_ARCH=avm2 libc.a
	# find bitcode (and ignore non-bitcode genned from .s files) and put
	# it in our lib
	rm -f $(BUILD)/lib/src/lib/libc/tmp/*
	$(AR) $(SDK)/usr/lib/libssp.a $(BUILD)/lib/src/lib/libc/stack_protector.o && cp $(SDK)/usr/lib/libssp.a $(SDK)/usr/lib/libssp_nonshared.a
	# we override these in thrStubs.c but leave them weak
	cd $(BUILD)/lib/src/lib/libc && $(SDK)/usr/bin/llvm-dis -o=_pthread_stubs.ll _pthread_stubs.o && sed -E 's/@pthread_(key_create|key_delete|getspecific|setspecific|once) =/@_d_u_m_m_y_\1 =/g' _pthread_stubs.ll | $(SDK)/usr/bin/llvm-as -o _pthread_stubs.o
	cd $(BUILD)/lib/src/lib/libc && rm -f libc.a && find . -name '*.o' -exec sh -c 'file {} | grep -v 86 > /dev/null' \; -print | xargs $(AR) libc.a
	cd $(BUILD)/posix && $(SDK)/usr/bin/gcc -emit-llvm -fno-stack-protector $(LIBHELPEROPTFLAGS) -I $(SRCROOT)/avm2_env/usr/src/lib/libc/include/ -fexceptions -c $(SRCROOT)/posix/libcHack.c
	cp -f $(BUILD)/lib/src/lib/libc/libc.a $(BUILD)/posix/libcHack.o $(SDK)/usr/lib/.

# TBD
libthr:
	rm -rf $(BUILD)/libthr
	mkdir -p $(BUILD)/libthr
	$(RSYNC) avm2_env/usr/src/lib/ $(BUILD)/libthr/
	cd $(BUILD)/libthr/libthr && $(SDK)/usr/bin/gcc -emit-llvm -fno-stack-protector $(LIBHELPEROPTFLAGS) -c $(SRCROOT)/posix/thrHelpers.c
	# CWARNFLAGS= because thr_exit() can return and pthread_exit() is marked noreturn (where?)...
	cd $(BUILD)/libthr/libthr && $(BMAKE) -j$(THREADS) SSP_CFLAGS="" MACHINE_ARCH=avm2 CWARNFLAGS= libthr.a
	# find bitcode (and ignore non-bitcode genned from .s files) and put
	# it in our lib
	cd $(BUILD)/libthr/libthr && rm -f libthr.a && find . -name '*.o' -exec sh -c 'file {} | grep -v 86 > /dev/null' \; -print | xargs $(AR) libthr.a
	cp -f $(BUILD)/libthr/libthr/libthr.a $(SDK)/usr/lib/.

# TBD
libm:
	cd compiler_rt && $(MAKE) clean && $(MAKE) avm2 CC="$(SDK)/usr/bin/gcc -emit-llvm" RANLIB=$(SDK)/usr/bin/ranlib AR=$(SDK_AR) VERBOSE=1
	$(SDK)/usr/bin/llvm-link -o $(BUILD)/libcompiler_rt.o compiler_rt/avm2/avm2/avm2/SubDir.lib/*.o
	$(SDK_NM) $(BUILD)/libcompiler_rt.o  | grep "T _" | sed 's/_//' | awk '{print $$3}' | sort | uniq > $(BUILD)/compiler_rt.txt
	cat $(BUILD)/compiler_rt.txt >> $(SDK)/public-api.txt
	cat $(SRCROOT)/$(DEPENDENCY_LLVM)/lib/CodeGen/SelectionDAG/TargetLowering.cpp | grep "Names\[RTLIB::" | awk '{print $$3}' | sed 's/"//g' | sed 's/;//' | sort | uniq > $(BUILD)/rtlib.txt
	cat avm2_env/rtlib-extras.txt >> $(BUILD)/rtlib.txt

	rm -rf $(BUILD)/msun/ $(BUILD)/libmbc $(SDK)/usr/lib/libm.a $(SDK)/usr/lib/libm.o
	mkdir -p $(BUILD)/msun
	$(RSYNC) avm2_env/usr/src/lib/ $(BUILD)/msun/
	cd $(BUILD)/msun/msun && $(BMAKE) -j$(THREADS) SSP_CFLAGS="" MACHINE_ARCH=avm2 libm.a
	# find bitcode (and ignore non-bitcode genned from .s files) and put
	# it in our lib
	cd $(BUILD)/msun/msun && rm -f libm.a && find . -name '*.o' -exec sh -c 'file {} | grep -v 86 > /dev/null' \; -print | xargs $(AR) libm.a
	# remove symbols for sin, cos, other things we support as intrinsics
	cd $(BUILD)/msun/msun && $(SDK_AR) sd libm.a s_cos.o s_sin.o e_pow.o e_sqrt.o
	$(SDK_AR) r $(SDK)/usr/lib/libm.a
	mkdir -p $(BUILD)/libmbc
	cd $(BUILD)/libmbc && $(SDK_AR) x $(BUILD)/msun/msun/libm.a
	cd $(BUILD)/libmbc && $(SDK)/usr/bin/llvm-link -o $(BUILD)/libmbc/libm.o $(BUILD)/libcompiler_rt.o *.o
	$(SDK)/usr/bin/opt -O3 -o $(SDK)/usr/lib/libm.o $(BUILD)/libmbc/libm.o
	$(SDK_NM) $(SDK)/usr/lib/libm.o | grep "T _" | sed 's/_//' | awk '{print $$3}' | sort | uniq > $(BUILD)/libm.bc.txt

# TBD
libBlocksRuntime:
	cd compiler_rt/BlocksRuntime && echo '#define HAVE_SYNC_BOOL_COMPARE_AND_SWAP_INT' > config.h && echo '#define HAVE_SYNC_BOOL_COMPARE_AND_SWAP_LONG' >> config.h
	cd compiler_rt/BlocksRuntime && $(SDK)/usr/bin/gcc -emit-llvm -c data.c -o data.o
	cd compiler_rt/BlocksRuntime && $(SDK)/usr/bin/gcc -emit-llvm -c runtime.c -o runtime.o
	cd compiler_rt/BlocksRuntime && $(AR) $(SDK)/usr/lib/libBlocksRuntime.a data.o runtime.o
	cp compiler_rt/BlocksRuntime/Block*.h $(SDK)/usr/include/

# ====================================================================================
# GCCLIBS
# ====================================================================================
# TBD
gcclibs:
	rm -rf $(BUILD)/llvm-gcc-42/$(TRIPLE)
	cd $(BUILD)/llvm-gcc-42 \
		&& $(MAKE) -j$(THREADS) FLASCC_INTERNAL_SDK_ROOT=$(SDK) CFLAGS_FOR_TARGET='-O2 -emit-llvm ' CXXFLAGS_FOR_TARGET='-O2 -emit-llvm ' all-target-libstdc++-v3 all-target-libgomp \
		&& $(MAKE) -j$(THREADS) FLASCC_INTERNAL_SDK_ROOT=$(SDK) install-target-libstdc++-v3 install-target-libgomp \
		&& find $(SDK) -name '*.gch' -type d | xargs rm -rf
	$(SDK)/usr/bin/ranlib $(SDK)/usr/lib/libstdc++.a
	$(SDK)/usr/bin/ranlib $(SDK)/usr/lib/libsupc++.a
	$(SDK)/usr/bin/ranlib $(SDK)/usr/lib/libgomp.a
	cp -f $(SDK)/usr/lib/gcc/$(TRIPLE)/4.2.1/include/omp.h $(SDK)/usr/include/
	rm -rf $(SDK)/usr/lib/gcc
	mkdir -p $(SDK)/usr/lib/stdlibs_abc
	cd $(BUILD)/posix && $(SDK)/usr/bin/g++ -emit-llvm -fno-stack-protector $(LIBHELPEROPTFLAGS) -c $(SRCROOT)/posix/AS3++.cpp
	cd $(BUILD)/posix && $(SDK)/usr/bin/llc -gendbgsymtable -jvm="$(JAVA)" -falcon-parallel -filetype=obj AS3++.o -o AS3++.abc
	cd $(BUILD)/posix && $(SDK_AR) crus $(SDK)/usr/lib/libAS3++.a AS3++.o
	cd $(BUILD)/posix && $(SDK_AR) crus $(SDK)/usr/lib/stdlibs_abc/libAS3++.a AS3++.abc

# ====================================================================================
# AS3WIG
# ====================================================================================
# TBD
as3wig:
	rm -rf $(BUILD)/as3wig
	mkdir -p $(BUILD)/as3wig/flascc
	cp -f $(SRCROOT)/tools/aet/AS3Wig.java $(BUILD)/as3wig/flascc/.
	cp -f $(SRCROOT)/tools/common/java/flascc/*.java $(BUILD)/as3wig/flascc/.
	cd $(BUILD)/as3wig && javac flascc/*.java -cp $(call nativepath,$(SDK)/usr/lib/compiler.jar)
	cd $(BUILD)/as3wig && echo "Main-Class: flascc.AS3Wig" > MANIFEST.MF
	cd $(BUILD)/as3wig && echo "Class-Path: compiler.jar" >> MANIFEST.MF
	cd $(BUILD)/as3wig && jar cmf MANIFEST.MF as3wig.jar flascc/*.class
	cp $(BUILD)/as3wig/as3wig.jar $(SDK)/usr/lib/.
	mkdir -p $(SDK)/usr/include/AS3++/
	cp -f $(SRCROOT)/tools/aet/AS3Wig.h $(SDK)/usr/include/AS3++/AS3Wig.h
	java -jar $(call nativepath,$(SDK)/usr/lib/as3wig.jar) -builtins -i $(call nativepath,$(SDK)/usr/lib/builtin.abc) -o $(call nativepath,$(SDK)/usr/include/AS3++/builtin)
	java -jar $(call nativepath,$(SDK)/usr/lib/as3wig.jar) -builtins -i $(call nativepath,$(SDK)/usr/lib/playerglobal.abc) -o $(call nativepath,$(SDK)/usr/include/AS3++/playerglobal)
	cp -f $(SRCROOT)/tools/aet/AS3Wig.cpp $(BUILD)/as3wig/
	echo "#include <AS3++/builtin.h>\n" > $(BUILD)/as3wig/AS3WigIncludes.h
	echo "#include <AS3++/playerglobal.h>\n" >> $(BUILD)/as3wig/AS3WigIncludes.h
	cd $(BUILD)/as3wig && $(SDK)/usr/bin/g++ -c -emit-llvm -I. AS3Wig.cpp -o Flash++.o
	cd $(BUILD)/as3wig && $(SDK_AR) crus $(SDK)/usr/lib/libFlash++.a Flash++.o

# ====================================================================================
# ABCSDTLIBS
# ====================================================================================

# TBD
abcflashpp:
	$(SDK)/usr/bin/llc -gendbgsymtable -jvmopt=-Xmx4G -jvm="$(JAVA)" -falcon-parallel -target-player -filetype=obj $(BUILD)/as3wig/Flash++.o -o $(BUILD)/as3wig/Flash++.abc
	$(SDK_AR) crus $(SDK)/usr/lib/stdlibs_abc/libFlash++.a $(BUILD)/as3wig/Flash++.abc

# TBD
abcstdlibs_more:
	mkdir -p $(SDK)/usr/lib/stdlibs_abc
	$(SDK)/usr/bin/llc -gendbgsymtable -jvm="$(JAVA)" -falcon-parallel -filetype=obj $(SDK)/usr/lib/crt1_c.o -o $(SDK)/usr/lib/stdlibs_abc/crt1_c.o
	$(SDK)/usr/bin/llc -gendbgsymtable -jvm="$(JAVA)" -falcon-parallel -filetype=obj $(SDK)/usr/lib/libm.o -o $(SDK)/usr/lib/stdlibs_abc/libm.o
	$(SDK)/usr/bin/llc -gendbgsymtable -jvm="$(JAVA)" -falcon-parallel -filetype=obj $(SDK)/usr/lib/libcHack.o -o $(SDK)/usr/lib/stdlibs_abc/libcHack.o

	mkdir -p $(BUILD)/libc_abc
	cd $(BUILD)/libc_abc && $(SDK_AR) x $(SDK)/usr/lib/libc.a
	cd $(BUILD)/libc_abc && cp -f $(SRCROOT)/avm2_env/misc/abcarchive.mk Makefile && SDK=$(SDK) $(MAKE) LLCOPTS=-jvm="$(JAVA)" -j$(THREADS)
	mv $(BUILD)/libc_abc/test.a $(SDK)/usr/lib/stdlibs_abc/libc.a

	mkdir -p $(BUILD)/libthr_abc
	cd $(BUILD)/libthr_abc && $(SDK_AR) x $(SDK)/usr/lib/libthr.a
	cd $(BUILD)/libthr_abc && cp -f $(SRCROOT)/avm2_env/misc/abcarchive.mk Makefile && SDK=$(SDK) $(MAKE) LLCOPTS=-jvm="$(JAVA)" -j$(THREADS)
	mv $(BUILD)/libthr_abc/test.a $(SDK)/usr/lib/stdlibs_abc/libthr.a

	mkdir -p $(BUILD)/libgcc_abc
	cd $(BUILD)/libgcc_abc && $(SDK_AR) x $(SDK)/usr/lib/libgcc.a
	cd $(BUILD)/libgcc_abc && cp -f $(SRCROOT)/avm2_env/misc/abcarchive.mk Makefile && SDK=$(SDK) $(MAKE) LLCOPTS=-jvm="$(JAVA)" -j$(THREADS)
	mv $(BUILD)/libgcc_abc/test.a $(SDK)/usr/lib/stdlibs_abc/libgcc.a

	mkdir -p $(BUILD)/libstdcpp_abc
	cd $(BUILD)/libstdcpp_abc && $(SDK_AR) x $(SDK)/usr/lib/libstdc++.a
	cd $(BUILD)/libstdcpp_abc && cp -f $(SRCROOT)/avm2_env/misc/abcarchive.mk Makefile && SDK=$(SDK) $(MAKE) LLCOPTS=-jvm="$(JAVA)" -j$(THREADS)
	mv $(BUILD)/libstdcpp_abc/test.a $(SDK)/usr/lib/stdlibs_abc/libstdc++.a

	mkdir -p $(BUILD)/libsupcpp_abc
	cd $(BUILD)/libsupcpp_abc && $(SDK_AR) x $(SDK)/usr/lib/libsupc++.a
	cd $(BUILD)/libsupcpp_abc && cp -f $(SRCROOT)/avm2_env/misc/abcarchive.mk Makefile && SDK=$(SDK) $(MAKE) LLCOPTS=-jvm="$(JAVA)" -j$(THREADS)
	mv $(BUILD)/libsupcpp_abc/test.a $(SDK)/usr/lib/stdlibs_abc/libsupc++.a

	# disable this until aliases work in our abc
	# mkdir -p $(BUILD)/libgomp_abc
	# cd $(BUILD)/libgomp_abc && $(SDK_AR) x $(SDK)/usr/lib/libgomp.a
	# cd $(BUILD)/libgomp_abc && cp -f $(SRCROOT)/avm2_env/misc/abcarchive.mk Makefile && SDK=$(SDK) $(MAKE) LLCOPTS=-jvm="$(JAVA)" -j$(THREADS)
	# mv $(BUILD)/libgomp_abc/test.a $(SDK)/usr/lib/stdlibs_abc/libgomp.a

	mkdir -p $(BUILD)/libBlocksRuntime_abc
	cd $(BUILD)/libBlocksRuntime_abc && $(SDK_AR) x $(SDK)/usr/lib/libBlocksRuntime.a
	cd $(BUILD)/libBlocksRuntime_abc && cp -f $(SRCROOT)/avm2_env/misc/abcarchive.mk Makefile && SDK=$(SDK) $(MAKE) LLCOPTS=-jvm="$(JAVA)" -j$(THREADS)
	mv $(BUILD)/libBlocksRuntime_abc/test.a $(SDK)/usr/lib/stdlibs_abc/libBlocksRuntime.a

# ====================================================================================
# CLEANUP
# ====================================================================================
# TBD
sdkcleanup:
	rm -rf $(SDK)/usr/share $(SDK)/usr/info $(SDK)/usr/man $(SDK)/usr/lib/x86_64 $(SDK)/usr/cmake_junk $(SDK)/usr/make_junk
	#mkdir -p $(SDK)/usr/share
	#mv $(HOST_SDK)/share_cmake $(SDK)/usr/share/$(DEPENDENCY_CMAKE)
	rm -f $(SDK)/usr/lib/*.la
	rm -f $(SDK)/usr/lib/crt1.o $(SDK)/usr/lib/crtbegin.o $(SDK)/usr/lib/crtbeginS.o $(SDK)/usr/lib/crtbeginT.o $(SDK)/usr/lib/crtend.o $(SDK)/usr/lib/crtendS.o $(SDK)/usr/lib/crti.o $(SDK)/usr/lib/crtn.o
	$(RSYNC) $(SRCROOT)/posix/avm2_tramp.cpp $(SDK)/usr/share/
	$(RSYNC) $(SRCROOT)/posix/vgl.c $(SDK)/usr/share/
	$(RSYNC) $(SRCROOT)/posix/Console.as $(SDK)/usr/share/
	$(RSYNC) $(SRCROOT)/posix/DefaultPreloader.as $(SDK)/usr/share/
	$(RSYNC) $(SRCROOT)/posix/vfs/HTTPBackingStore.as $(SDK)/usr/share/
	$(RSYNC) $(SRCROOT)/posix/vfs/DefaultVFS.as $(SDK)/usr/share/
	$(RSYNC) $(SRCROOT)/posix/vfs/ISpecialFile.as $(SDK)/usr/share/
	$(RSYNC) $(SRCROOT)/posix/vfs/IBackingStore.as $(SDK)/usr/share/
	$(RSYNC) $(SRCROOT)/posix/vfs/IVFS.as $(SDK)/usr/share/
	$(RSYNC) $(SRCROOT)/posix/vfs/InMemoryBackingStore.as $(SDK)/usr/share/
	$(RSYNC) $(SRCROOT)/posix/vfs/LSOBackingStore.as $(SDK)/usr/share/
	$(RSYNC) $(SRCROOT)/posix/vfs/URLLoaderVFS.as $(SDK)/usr/share/
	$(RSYNC) --exclude "*.xslt" --exclude "*.html" --exclude ASDoc_Config.xml --exclude overviews.xml $(BUILDROOT)/tempdita/ $(SDK)/usr/share/asdocs

# TBD
finalcleanup:
	rm -f $(SDK)/usr/lib/*.la
	rm -rf $(SDK)/usr/share/aclocal $(SDK)/usr/share/doc $(SDK)/usr/share/man $(SDK)/usr/man $(SDK)/usr/share/info

# ====================================================================================
# EXTRA TOOLS
# ====================================================================================

# Tamarin Shell built without debugging
tr:
	rm -rf $(BUILD)/tr
	mkdir -p $(BUILD)/tr
	cd $(BUILD)/tr && rm -f Makefile && AR=$(NATIVE_AR) CC=$(CC) CXX=$(CXX) CFLAGS=$(HOST_CFLAGS) $(TAMARINCONFIG) --disable-debugger
	cd $(BUILD)/tr && AR=$(NATIVE_AR) CC=$(CC) CXX=$(CXX) $(MAKE) -j$(THREADS)
	cp -f $(BUILD)/tr/shell/avmshell $(SDK)/usr/bin/avmshell
	cd $(SRCROOT)/$(DEPENDENCY_AVMPLUS)/utils && curdir=$(SRCROOT)/$(DEPENDENCY_AVMPLUS)/utils ASC=$(ASC) $(MAKE) -f manifest.mk utils
	cd $(BUILD)/abclibs && $(ASC2) $(call nativepath,$(SRCROOT)/$(DEPENDENCY_AVMPLUS)/utils/projectormake.as) -outdir . -out projectormake
ifneq (,$(findstring cygwin,$(PLATFORM)))
	$(SDK)/usr/bin/avmshell $(BUILD)/abclibs/projectormake.abc -- -o $(SDK)/usr/bin/abcdump$(EXEEXT) $(SDK)/usr/bin/avmshell $(BUILD)/abcdump.abc -- -Djitordie
	chmod a+x $(SDK)/usr/bin/abcdump$(EXEEXT)
endif

# Tamarin Shell built with debugging
trd:
	rm -rf $(BUILD)/trd
	mkdir -p $(BUILD)/trd
	cd $(BUILD)/trd && rm -f Makefile && AR=$(NATIVE_AR) CC=$(CC) CXX=$(CXX) CFLAGS=$(HOST_CFLAGS) $(TAMARINCONFIG) --enable-debugger
	cd $(BUILD)/trd && AR=$(NATIVE_AR) CC=$(CC) CXX=$(CXX) $(MAKE) -j$(THREADS)
	cp -f $(BUILD)/trd/shell/avmshell $(SDK)/usr/bin/avmshell-release-debugger

SWIG_LDFLAGS=-L$(BUILD)/llvm-debug/lib
SWIG_LIBS=-lLLVMAVM2ShimInfo -lLLVMAVM2ShimCodeGen -lclangFrontend -lclangCodeGen -lclangDriver -lclangParse -lclangSema -lclangAnalysis -lclangLex -lclangAST -lclangBasic -lLLVMSelectionDAG -lLLVMCodeGen -lLLVMTarget -lLLVMMC -lLLVMScalarOpts -lLLVMTransformUtils -lLLVMAnalysis -lclangSerialization -lLLVMCore -lLLVMSupport 
SWIG_CXXFLAGS=-I$(SRCROOT)/avm2_env/misc/ -I$(SRCROOT)/$(DEPENDENCY_LLVM)/include -I$(BUILD)/llvm-debug/include -I$(SRCROOT)/$(DEPENDENCY_LLVM)/tools/clang/include -I$(BUILD)/llvm-debug/tools/clang/include -I$(SRCROOT)/$(DEPENDENCY_LLVM)/tools/clang/lib -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS -fno-rtti -g -Wno-long-long
# VPMedia: Why delete, I would want a full featured swig shipped as possible, so deletion is disabled below
SWIG_DIRS_TO_DELETE=allegrocl chicken clisp csharp d gcj go guile java lua modula3 mzscheme ocaml octave perl5 php pike python r ruby tcl

# Build SWIG
swig:
	rm -rf $(BUILD)/swig
	mkdir -p $(BUILD)/swig
	#unpack PCRE dependency
	cp -f packages/pcre-8.20.tar.gz $(BUILD)/swig
	#configure PCRE dependency
	cd $(BUILD)/swig && CC=$(CC) CXX=$(CXX) CFLAGS=$(HOST_CFLAGS) $(SRCROOT)/$(DEPENDENCY_SWIG)/Tools/pcre-build.sh --build=$(BUILD_TRIPLE) --host=$(HOST_TRIPLE) --target=$(HOST_TRIPLE)
	#initialize SWIG
	#cd $(SRCROOT)/$(DEPENDENCY_SWIG) && ./autogen.sh --build=$(BUILD_TRIPLE) --host=$(HOST_TRIPLE) --target=$(HOST_TRIPLE)
	#configure SWIG
	cd $(BUILD)/swig && CC=$(CC) CXX=$(CXX) CFLAGS="-g $(HOST_CFLAGS)" LDFLAGS="$(SWIG_LDFLAGS) $(HOST_CFLAGS)" LIBS="$(SWIG_LIBS)" CXXFLAGS="$(SWIG_CXXFLAGS) $(HOST_CFLAGS)" $(SRCROOT)/$(DEPENDENCY_SWIG)/configure --prefix=$(SDK)/usr --disable-ccache --without-maximum-compile-warnings --build=$(BUILD_TRIPLE) --host=$(HOST_TRIPLE) --target=$(HOST_TRIPLE)
	#make and install SWIG
	cd $(BUILD)/swig && $(MAKE) && $(MAKE) install
	#$(foreach var, $(SWIG_DIRS_TO_DELETE), rm -rf $(SDK)/usr/share/swig/3.0.0/$(var);)

# Run SWIG Tests
swigtests:
	# reconfigure so that makefile is up to date (in case Makefile.in changed)
	cd $(BUILD)/swig && CFLAGS=-g LDFLAGS="$(SWIG_LDFLAGS)" LIBS="$(SWIG_LIBS)" \
		CXXFLAGS="$(SWIG_CXXFLAGS)" $(SRCROOT)/$(DEPENDENCY_SWIG)/configure --prefix=$(SDK)/usr --disable-ccache
	rm -rf $(BUILD)/swig/Examples/as3
	cp -R $(SRCROOT)/$(DEPENDENCY_SWIG)/Examples/as3 $(BUILD)/swig/Examples
	rm -rf $(BUILD)/swig/Lib/
	mkdir -p $(BUILD)/swig/Lib/as3
	cp -R $(SRCROOT)/$(DEPENDENCY_SWIG)/Lib/as3/* $(BUILD)/swig/Lib/as3
	cp $(SRCROOT)/$(DEPENDENCY_SWIG)/Lib/*.i $(BUILD)/swig/Lib
	cp $(SRCROOT)/$(DEPENDENCY_SWIG)/Lib/*.swg $(BUILD)/swig/Lib
	cd $(BUILD)/swig && $(MAKE) check-as3-examples

# Generate Virtual File System ZLib Dependency
genfs:
	rm -rf $(BUILD)/zlib-native
	mkdir -p $(BUILD)/zlib-native
	$(RSYNC) $(SRCROOT)/$(DEPENDENCY_ZLIB)/ $(BUILD)/zlib-native
	cd $(BUILD)/zlib-native && AR=$(NATIVE_AR) CC=$(CC) CXX=$(CXX) CFLAGS=$(HOST_CFLAGS) ./configure --static && $(MAKE) 
	cd $(BUILD)/zlib-native/contrib/minizip/ && $(MAKE) 
	$$CC -Wall -I$(BUILD)/zlib-native/contrib/minizip -o $(SDK)/usr/bin/genfs$(EXEEXT) $(BUILD)/zlib-native/contrib/minizip/zip.o $(BUILD)/zlib-native/contrib/minizip/ioapi.o $(BUILD)/zlib-native/libz.a $(SRCROOT)/tools/vfs/genfs.c $(HOST_CFLAGS)

# Build GDB Debugger
gdb:
	rm -rf $(BUILD)/$(DEPENDENCY_GDB)
	mkdir -p $(BUILD)/$(DEPENDENCY_GDB)
	cd $(BUILD)/$(DEPENDENCY_GDB) && CFLAGS="-I$(SRCROOT)/avm2_env/misc $(HOST_CFLAGS)" $(SRCROOT)/$(DEPENDENCY_GDB)/configure \
		--build=$(BUILD_TRIPLE) --host=$(HOST_TRIPLE) --target=avm2-elf && $(MAKE)
	cp -f $(BUILD)/$(DEPENDENCY_GDB)/gdb/gdb$(EXEEXT) $(SDK)/usr/bin/
	cp -f $(SRCROOT)/tools/flascc.gdb $(SDK)/usr/share/
	cp -f $(SRCROOT)/tools/flascc-run.gdb $(SDK)/usr/share/
	cp -f $(SRCROOT)/tools/flascc-init.gdb $(SDK)/usr/share/


# ====================================================================================
# Submit tests
# ====================================================================================

# Test HelloWorld.C
test_hello_c:
	# Cleaning test folder
	@rm -rf $(BUILD)/test_hello_c
	@mkdir -p $(BUILD)/test_hello_c
	# Assembling BitCode Output (BC)
	cd $(BUILD)/test_hello_c && $(SDK_CC) -c -g -O0 $(SRCROOT)/test/hello.c -emit-llvm -o hello.bc
	# Assembling ABC Output (OBJ)
	cd $(BUILD)/test_hello_c && $(SDK)/usr/bin/llc -jvm="$(JAVA)" hello.bc -o hello.abc -filetype=obj
	# Assembling AS3 Output (ASM)
	cd $(BUILD)/test_hello_c && $(SDK)/usr/bin/llc -jvm="$(JAVA)" hello.bc -o hello.as -filetype=asm
	# Assembling SWF Output
	cd $(BUILD)/test_hello_c && $(SDK_CC) -save-temps -emit-swf -swf-size=320x240 -O0 -g hello.abc -o hello.swf
	# Assembling SWF Output (Optimized)
	cd $(BUILD)/test_hello_c && $(SDK_CC) -save-temps -emit-swf -swf-size=320x240 -O4 $(SRCROOT)/test/hello.c -o hello-opt.swf

# Test HelloWorld.CPP
test_hello_cpp:
	# Cleaning test folder
	@rm -rf $(BUILD)/test_hello_cpp
	@mkdir -p $(BUILD)/test_hello_cpp
	# Assembling Native Output
	cd $(BUILD)/test_hello_cpp && $(SDK_CXX) -g -O0 $(SRCROOT)/test/hello.cpp -o hello-cpp && ./hello-cpp /key1=value1 /key2=value2
	# Assembling SWF Output
	cd $(BUILD)/test_hello_cpp && $(SDK_CXX) -save-temps -emit-swf -swf-size=320x240 -O0 $(SRCROOT)/test/hello.cpp -o hello-cpp.swf
	# Assembling SWF Output (Optimized)
	cd $(BUILD)/test_hello_cpp && $(SDK_CXX) -save-temps -emit-swf -swf-size=320x240 -O4 $(SRCROOT)/test/hello.cpp -o hello-cpp-opt.swf

# Test POSIX Threads - C
test_pthreads_c_shell:
	# Cleaning test folder
	@rm -rf $(BUILD)/test_pthreads_c_shell
	@mkdir -p $(BUILD)/test_pthreads_c_shell
	# Assembling SWF Output
	cd $(BUILD)/test_pthreads_c_shell && $(SDK_CC) -O0 -pthread -save-temps $(SRCROOT)/test/pthread_test.c -o pthread_test
	# Assembling SWF Output (Optimized)
	cd $(BUILD)/test_pthreads_c_shell && $(SDK_CC) -O4 -pthread -save-temps $(SRCROOT)/test/pthread_test.c -o pthread_test_optimized
	# Running Output
	cd $(BUILD)/test_pthreads_c_shell && ./pthread_test &> $(BUILD)/test_pthreads_c_shell/pthread_test.txt
	# Running Output (Optimized)
	cd $(BUILD)/test_pthreads_c_shell && ./pthread_test_optimized &> $(BUILD)/test_pthreads_c_shell/pthread_test_optimized.txt

# Test POSIX Threads - C
test_pthreads_c_swf:
	# Cleaning test folder
	@rm -rf $(BUILD)/test_pthreads_c_swf
	@mkdir -p $(BUILD)/test_pthreads_c_swf
	# Assembling SWC
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -save-temps $(SRCROOT)/test/pthread_test.c -emit-swc=com.adobe.flascc -o pthread_test_optimized.swc
	# Assembling SWF
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O0 -pthread -emit-swf -save-temps $(SRCROOT)/test/pthread_test.c -o pthread_test.swf
	# Assembling SWF (Optimized)
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -emit-swf -save-temps $(SRCROOT)/test/pthread_test.c -o pthread_test_optimized.swf
	# Assembling SWFs (Optimized)
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -emit-swf $(SRCROOT)/test/pthread_cancel.c -o pthread_cancel.swf
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -emit-swf $(SRCROOT)/test/pthread_async_cancel.c -o pthread_async_cancel.swf
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -emit-swf $(SRCROOT)/test/pthread_create.c -o pthread_create.swf
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -emit-swf $(SRCROOT)/test/pthread_create_test.c -o pthread_create_test.swf
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -emit-swf $(SRCROOT)/test/pthread_mutex_test.c -o pthread_mutex_test.swf
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -emit-swf $(SRCROOT)/test/pthread_mutex_test2.c -o pthread_mutex_test2.swf
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -emit-swf $(SRCROOT)/test/pthread_malloc_test.c -o pthread_malloc_test.swf
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -emit-swf $(SRCROOT)/test/pthread_specific.c -o pthread_specific.swf
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -emit-swf $(SRCROOT)/test/pthread_suspend.c -o pthread_suspend.swf
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -emit-swf $(SRCROOT)/test/thr_kill.c -o thr_kill.swf
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -emit-swf $(SRCROOT)/test/peterson.c -o peterson.swf
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -emit-swf -DORDER_STRENGTH=1 $(SRCROOT)/test/peterson.c -o peterson_nofence.swf
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -emit-swf $(SRCROOT)/test/newThread.c -o newThread.swf
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -emit-swf $(SRCROOT)/test/avm2_conc.c -o avm2_conc.swf
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -emit-swf $(SRCROOT)/test/avm2_mutex.c -o avm2_mutex.swf
	cd $(BUILD)/test_pthreads_c_swf && $(SDK_CC) -O4 -pthread -emit-swf $(SRCROOT)/test/avm2_mutex2.c -o avm2_mutex2.swf

# Test POSIX Threads - CPP
test_pthreads_cpp_swf:
	# Cleaning test folder
	@rm -rf $(BUILD)/test_pthreads_cpp_swf
	@mkdir -p $(BUILD)/test_pthreads_cpp_swf
	# Assembling SWFs
	cd $(BUILD)/test_pthreads_cpp_swf && $(SDK_CXX) -O4 -emit-swf -pthread $(SRCROOT)/test/AS3++mt.cpp -lAS3++ -o AS3++mt.swf
	cd $(BUILD)/test_pthreads_cpp_swf && $(SDK_CXX) -O4 -emit-swf -pthread $(SRCROOT)/test/AS3++mt1.cpp -lAS3++ -o AS3++mt1.swf
	cd $(BUILD)/test_pthreads_cpp_swf && $(SDK_CXX) -O4 -emit-swf -pthread $(SRCROOT)/test/AS3++mt2.cpp -lAS3++ -o AS3++mt2.swf
	cd $(BUILD)/test_pthreads_cpp_swf && $(SDK_CXX) -O4 -emit-swf -pthread $(SRCROOT)/test/AS3++mt3.cpp -lAS3++ -o AS3++mt3.swf

# Test POSIX VFS
test_posix:
	# Cleaning test folder
	@rm -rf $(BUILD)/test_posix
	@mkdir -p $(BUILD)/test_posix
	# Assembling VFS
	$(SDK)/usr/bin/genfs --name my.test.BackingStore $(SRCROOT)/test/zipfsroot $(BUILD)/test_posix/alcfs
	# Assembling ABC
	cd $(BUILD)/test_posix && $(ASC2) \
		-import $(call nativepath,$(SDK)/usr/lib/BinaryData.abc) \
		-import $(call nativepath,$(SDK)/usr/lib/playerglobal.abc) \
		-import $(call nativepath,$(SDK)/usr/lib/ISpecialFile.abc) \
		-import $(call nativepath,$(SDK)/usr/lib/IBackingStore.abc) \
		-import $(call nativepath,$(SDK)/usr/lib/IVFS.abc) \
		-import $(call nativepath,$(SDK)/usr/lib/AlcVFSZip.abc) \
		-import $(call nativepath,$(SDK)/usr/lib/InMemoryBackingStore.abc) \
		-import $(call nativepath,$(SDK)/usr/lib/PlayerKernel.abc) \
		$(call nativepath, $(BUILD)/test_posix/alcfsBackingStore.as) -outdir . -out alcfs
	# Assembling SWF
	cd $(BUILD)/test_posix && $(SDK_CC) -emit-swf -O0 -swf-version=15 $(call nativepath,$(SDK)/usr/lib/AlcVFSZip.abc) alcfs.abc $(SRCROOT)/test/fileio.c -o posixtest.swf

# Test with SciMark
test_scimark_shell:
	# Cleaning test folder
	@rm -rf $(BUILD)/test_scimark_shell
	@mkdir -p $(BUILD)/test_scimark_shell
	# Assembling Native
	cd $(BUILD)/test_scimark_shell && $(SDK_CC) -O4 $(SRCROOT)/scimark2_1c/*.c -o scimark2 -save-temps
	# Running Native
	$(BUILD)/test_scimark_shell/scimark2 &> $(BUILD)/test_scimark_shell/result.txt

# Test with SciMark SWF
test_scimark_swf:
	# Cleaning test folder
	@rm -rf $(BUILD)/test_scimark_swf
	@mkdir -p $(BUILD)/test_scimark_swf
	# Assembling SWFs
	cd $(BUILD)/test_scimark_swf && $(SDK_CC) -O4 -swf-version=17 $(SRCROOT)/scimark2_1c/*.c -emit-swf -swf-size=400x400 -o scimark2-SWF17.swf
	cd $(BUILD)/test_scimark_swf && $(SDK_CC) -O4 $(SRCROOT)/scimark2_1c/*.c -emit-swf -swf-size=400x400 -o scimark2.swf
	cd $(BUILD)/test_scimark_swf && $(SDK_CC) -O4 $(SRCROOT)/scimark2_1c/*.c -emit-swf -swf-size=400x400 -o scimark2v18.swf

# TBD
test_sjlj:
	# Cleaning test folder
	@rm -rf $(BUILD)/test_sjlj
	@mkdir -p $(BUILD)/test_sjlj
	# Assembling Native
	cd $(BUILD)/test_sjlj && $(SDK_CXX) -O0 $(SRCROOT)/test/sjljtest.c -v -o sjljtest -save-temps
	# Running Native
	$(BUILD)/test_sjlj/sjljtest &> $(BUILD)/test_sjlj/result.txt
	diff --strip-trailing-cr $(BUILD)/test_sjlj/result.txt $(SRCROOT)/test/sjljtest.expected.txt

# TBD
test_sjlj_opt:
	# Cleaning test folder
	@rm -rf $(BUILD)/test_sjlj_opt
	@mkdir -p $(BUILD)/test_sjlj_opt
	# Assembling Native
	cd $(BUILD)/test_sjlj_opt && $(SDK_CXX) -O4 $(SRCROOT)/test/sjljtest.c -o sjljtest -save-temps
	# Running Native
	$(BUILD)/test_sjlj_opt/sjljtest &> $(BUILD)/test_sjlj_opt/result.txt
	diff --strip-trailing-cr $(BUILD)/test_sjlj_opt/result.txt $(SRCROOT)/test/sjljtest.expected.txt

# TBD
test_eh:
	# Cleaning test folder
	@rm -rf $(BUILD)/test_eh
	@mkdir -p $(BUILD)/test_eh
	# Assembling Native
	cd $(BUILD)/test_eh && $(SDK_CXX) -O0 $(SRCROOT)/test/ehtest.cpp -o ehtest -save-temps
	# Running Native
	-$(BUILD)/test_eh/ehtest &> $(BUILD)/test_eh/result.txt
	diff --strip-trailing-cr $(BUILD)/test_eh/result.txt $(SRCROOT)/test/ehtest.expected.txt

# TBD
test_eh_opt:
	# Cleaning test folder
	@rm -rf $(BUILD)/test_eh_opt
	@mkdir -p $(BUILD)/test_eh_opt
	# Assembling Native
	cd $(BUILD)/test_eh_opt && $(SDK_CXX) -O4 $(SRCROOT)/test/ehtest.cpp -o ehtest -save-temps
	# Running Native
	-$(BUILD)/test_eh_opt/ehtest &> $(BUILD)/test_eh_opt/result.txt
	diff --strip-trailing-cr $(BUILD)/test_eh_opt/result.txt $(SRCROOT)/test/ehtest.expected.txt

# TBD
test_as3interop:
	# Cleaning test folder
	@rm -rf $(BUILD)/test_as3interop
	@mkdir -p $(BUILD)/test_as3interop
	# Assembling Native
	cd $(BUILD)/test_as3interop && $(SDK_CXX) -O4 $(SRCROOT)/test/as3interoptest.c -o as3interoptest -save-temps
	# Running Native
	$(BUILD)/test_as3interop/as3interoptest &> $(BUILD)/test_as3interop/result.txt

# Tests Listing of Symbols from ASM and ABC Object Formats
# 'llvm-as': Reads from human readable LLVM assembly language, translates it to LLVM byte-code
# 'llc': Compiles LLVM byte-code into assembly language
# 'nm': Lists the symbols from object files
test_symbols:
	# Cleaning test folder
	@rm -rf $(BUILD)/test_symbols
	mkdir -p $(BUILD)/test_symbols
	# Assembling Native
	cd $(BUILD)/test_symbols && $(SDK)/usr/bin/llvm-as $(SRCROOT)/test/symboltest.ll -o symboltest.bc
	cd $(BUILD)/test_symbols && $(SDK)/usr/bin/llc -jvm=$(JAVA) symboltest.bc -filetype=asm -o symboltest.s
	cd $(BUILD)/test_symbols && $(SDK)/usr/bin/llc -jvm=$(JAVA) symboltest.bc -filetype=obj -o symboltest.abc
	cd $(BUILD)/test_symbols && $(SDK_NM) symboltest.abc | grep symbolTest > syms.abc.txt
	cd $(BUILD)/test_symbols && $(SDK_NM) symboltest.bc | grep symbolTest > syms.bc.txt
	# Generating Result
	diff --strip-trailing-cr $(BUILD)/test_symbols/*.txt

# ====================================================================================
# Samples and Examples
# ====================================================================================

# Samples shipped with the SDK
samples:
	cd samples && PATH=$(SDK)/usr/bin:$(PATH) $(MAKE) UNAME=$(UNAME) FLASCC=$(SDK) FLEX=$(FLEX_SDK_HOME)

# Used to clean the samples
clean_samples:
	cd samples && PATH=$(SDK)/usr/bin:$(PATH) $(MAKE) UNAME=$(UNAME) FLASCC=$(SDK) FLEX=$(FLEX_SDK_HOME) clean

# ====================================================================================
# Extra Tests
# ====================================================================================

# Check headers for ASM
checkasm:
	rm -rf $(BUILD)/libtoabc
	@mkdir -p $(BUILD)/logs/libtoabc
	@libs=`find $(SDK) -name "*.a"`; \
	omittedlibs="libjpeg.a\nlibpng\nlibz.a" ; \
	omittedlibs=`echo $$omittedlibs` ; \
	libs=`echo "$$libs" | grep -F -v "$$omittedlibs"` ; \
	echo "Compiling SDK libraries to ABC" ; \
	for lib in $$libs ; do \
		shortlib=`basename $$lib` ; \
		echo "- checking $$lib" ; \
		$(MAKE) libtoabc LIB=$$lib &> $(BUILD)/logs/libtoabc/$$shortlib.txt ; \
		mret=$$? ; \
		if [ $$mret -ne 0 ] ; then \
		echo "Failed to build abc: $$lib" ;\
		cat $(BUILD)/logs/libtoabc/$$shortlib.txt ;\
		exit 1 ; \
		fi ; \
	done
	@echo "Checking headers for asm"
	$(PYTHON) $(SRCROOT)/tools/search_headers.py $(SDK) $(BUILD)/header-search

# Helper target for 'checkasm'
libtoabc:
	mkdir -p $(BUILD)/libtoabc/`basename $(LIB)`
	cd $(BUILD)/libtoabc/`basename $(LIB)` && $(SDK_AR) x $(LIB)
	@abcdir=$(BUILD)/libtoabc/`basename $(LIB)` ; \
	numos=`find $$abcdir -maxdepth 1 -name '*.o' | wc -l` ; \
	if [$$numos -gt 0 ] ; then \
	cd $(BUILD)/libtoabc/`basename $(LIB)` && cp -f $(SRCROOT)/avm2_env/misc/abcarchive.mk Makefile && SDK=$(SDK) $(MAKE) LLCOPTS=-jvm="$(JAVA)" -j$(THREADS) ; \
	fi 

# Deprecated test (Source missing)
speccpu2006: # works on mac only! (and probably requires local tweaks to alchemy.cfg and mac32.cfg)
	@rm -rf $(BUILD)/speccpu2006
	@mkdir -p $(BUILD)/speccpu2006
	cd $(BUILD)/speccpu2006 && curl http://alchemy.corp.adobe.com/speccpu2006.tar.bz2 | tar xvf -
	cd $(BUILD)/speccpu2006/speccpu2006 && cat $(SRCROOT)/test/speccpu2006/install.sh.ed | ed install.sh # build install2.sh w/ hardcoded arch=mac32-x86
	cd $(BUILD)/speccpu2006/speccpu2006 && chmod +x install2.sh && chmod +x tools/bin/macosx-x86/spec* && chmod +w MANIFEST && echo y | SPEC= ./install2.sh
	cd $(BUILD)/speccpu2006/speccpu2006 && cp $(SRCROOT)/test/speccpu2006/*.cfg config/. && chmod +w config/*.cfg
	cd $(BUILD)/speccpu2006/speccpu2006 && (source shrc && time runspec --config=alchemy.cfg --tune=base --loose --action build int fp | tee alchemy.build.log)
	cd $(BUILD)/speccpu2006/speccpu2006 && (source shrc && time runspec --config=mac32.cfg --tune=base --loose --action build int fp | tee mac32.build.log)
	cd $(BUILD)/speccpu2006/speccpu2006 && (source shrc && time runspec --config=alchemy.cfg --tune=base --loose --action validate int fp | tee -a alchemy.run.log)
	cd $(BUILD)/speccpu2006/speccpu2006 && (source shrc && time runspec --config=mac32.cfg --tune=base --loose --action validate int fp | tee -a mac32.run.log)

# Helper lib for GCC tests
dejagnu:
	mkdir -p $(BUILD)/dejagnu
	cd $(BUILD)/dejagnu && $(SRCROOT)/dejagnu-1.5/configure --prefix=$(BUILD)/dejagnu && $(MAKE) install

RUNGCCTESTS=mkdir -p $(BUILD)/gcctests/$@ && cd $(BUILD)/gcctests/$@ && LD_LIBRARY_PATH="/" PATH="$(SDK)/usr/bin:$(PATH)" $(BUILD)/dejagnu/bin/runtest --all --srcdir $(SRCROOT)/llvm-gcc-4.2-2.9/gcc/testsuite --target_board=$(TRIPLE)

CTORTUREDIRS= \
compat \
compile \
execute \
unsorted

GCCTESTDIRS= \
g++.apple \
g++.dg \
g++.old-deja \
gcc.apple \
gcc.dg \
gcc.misc-tests \
gcc.target \
gcc.test-framework 

gcctorture/%:
	-$(RUNGCCTESTS) --tool gcc --directory $(SRCROOT)/llvm-gcc-4.2-2.9/gcc/testsuite/gcc.c-torture $(@:gcctorture/%=%).exp

gxxtorture/%:
	-$(RUNGCCTESTS) --tool g++ --directory $(SRCROOT)/llvm-gcc-4.2-2.9/gcc/testsuite/gcc.c-torture $(@:gxxtorture/%=%).exp

gccrun/%:
	-$(RUNGCCTESTS) --tool gcc --directory $(SRCROOT)/llvm-gcc-4.2-2.9/gcc/testsuite/$(@:gccrun/%=%)

gxxrun/%:
	-$(RUNGCCTESTS) --tool g++ --directory $(SRCROOT)/llvm-gcc-4.2-2.9/gcc/testsuite/$(@:gxxrun/%=%)

# TBD
gcctests:
	$(MAKE) dejagnu
	cp -f $(SRCROOT)/tools/$(TRIPLE).exp $(BUILD)/dejagnu/share/dejagnu/baseboards/
	chmod u+rw $(BUILD)/dejagnu/share/dejagnu/baseboards/*
	$(MAKE) -j$(THREADS) allgcctests

# TBD
allgcctests: $(CTORTUREDIRS:%=gcctorture/%) $(CTORTUREDIRS:%=gxxtorture/%) $(GCCTESTDIRS:%=gccrun/%) $(GCCTESTDIRS:%=gxxrun/%)
	cat $(BUILD)/gcctests/*/*/gcc.log  > $(BUILD)/gcctests/gcc.log
	cat $(BUILD)/gcctests/*/*/g++.log  > $(BUILD)/gcctests/g++.log

# TBD
ieeetests_conversion:
	rm -rf $(BUILD)/ieeetests_conversion
	mkdir -p $(BUILD)/ieeetests_conversion
	$(RSYNC) $(SRCROOT)/test/IeeeCC754/ $(BUILD)/ieeetests_conversion
	echo "b\nb\na" > $(BUILD)/ieeetests_conversion/answers
	cd $(BUILD)/ieeetests_conversion && PATH=$(SDK)/usr/bin:$(PATH) ./dotests.sh < answers

# TBD
ieeetests_basicops:
	rm -rf $(BUILD)/ieeetests_basicops
	mkdir -p $(BUILD)/ieeetests_basicops
	$(RSYNC) $(SRCROOT)/test/IeeeCC754/ $(BUILD)/ieeetests_basicops
	echo "a\nb\na" > $(BUILD)/ieeetests_basicops/answers
	cd $(BUILD)/ieeetests_basicops && PATH=$(SDK)/usr/bin:$(PATH) ./dotests.sh < answers

# ====================================================================================
# DEPLOY
# ====================================================================================
# Deploy SDK 
deploy:
	$(MAKE) clean_samples
	rm -rf $(BUILDROOT)/staging
	mkdir -p $(BUILDROOT)/staging
	#Deploying SDK
	$(RSYNC) $(SDK) $(BUILDROOT)/staging/
	#Deploying Samples
	$(RSYNC) $(SRCROOT)/samples $(BUILDROOT)/staging/
	#Deploying Docs
	$(RSYNC) $(SRCROOT)/README.html $(BUILDROOT)/staging/
	$(RSYNC) $(SRCROOT)/docs $(BUILDROOT)/staging/
	$(RSYNC) $(BUILDROOT)/apidocs $(BUILDROOT)/staging/docs/
ifneq (,$(findstring cygwin,$(PLATFORM)))
	#Deploying Cygwin
	$(RSYNC) $(SRCROOT)/tools/cygwinx/ $(BUILDROOT)/staging/
endif
	#Cleaning up temp files
	rm -f $(BUILDROOT)/staging/sdk/usr/bin/gccbug*
	find $(BUILDROOT)/staging/ | grep "\.DS_Store$$" | xargs rm -f
	#Emitting SDK descriptor
	@echo  "<?xml version=\"1.0\"?>" > $(BUILDROOT)/staging/crossbridge-sdk-description.xml
	@echo  "<crossbridge-sdk-description>" >> $(BUILDROOT)/staging/crossbridge-sdk-description.xml
	@echo  "<name>$(SDKNAME)</name>" >> $(BUILDROOT)/staging/crossbridge-sdk-description.xml
	@echo  "<version>$(FLASCC_VERSION_MAJOR).$(FLASCC_VERSION_MINOR).$(FLASCC_VERSION_PATCH)</version>" >> $(BUILDROOT)/staging/crossbridge-sdk-description.xml
	@echo  "<build>$(FLASCC_VERSION_BUILD)</build>" >> $(BUILDROOT)/staging/crossbridge-sdk-description.xml
	@echo  "</crossbridge-sdk-description>" >> $(BUILDROOT)/staging/crossbridge-sdk-description.xml
	#Flattening symbolic links
	find $(BUILDROOT)/staging/sdk -type l | xargs rm
	$(RSYNC) $(BUILDROOT)/staging/sdk/usr/platform/*/ $(BUILDROOT)/staging/sdk/usr
	rm -rf $(BUILDROOT)/staging/sdk/usr/platform
	#Packaging
ifneq (,$(findstring cygwin,$(PLATFORM)))
		cd $(BUILDROOT)/staging/ && zip -qr $(BUILDROOT)/$(SDKNAME).zip *
else
	mkdir -p $(BUILDROOT)/dmgmount
	rm -f $(BUILDROOT)/$(SDKNAME).dmg $(BUILDROOT)/$(SDKNAME)-tmp.dmg
	cp -f $(SRCROOT)/tools/Base.dmg $(BUILDROOT)/$(SDKNAME)-tmp.dmg
	chmod u+rw $(BUILDROOT)/$(SDKNAME)-tmp.dmg
	hdiutil resize -size 1G $(BUILDROOT)/$(SDKNAME)-tmp.dmg
	hdiutil attach $(BUILDROOT)/$(SDKNAME)-tmp.dmg -readwrite -mountpoint $(BUILDROOT)/dmgmount
	rm -f $(BUILDROOT)/staging/.DS_Store
	$(RSYNC) $(BUILDROOT)/staging/ $(BUILDROOT)/dmgmount/
	mv $(BUILDROOT)/dmgmount/.fseventsd $(BUILDROOT)/
	hdiutil detach $(BUILDROOT)/dmgmount
	hdiutil convert $(BUILDROOT)/$(SDKNAME)-tmp.dmg -format UDZO -imagekey zlib-level=9 -o $(BUILDROOT)/$(SDKNAME).dmg
	rm -f $(BUILDROOT)/$(SDKNAME)-tmp.dmg
endif

.PHONY: bmake posix binutils docs gcc samples patches
