SDK_HOME := $(HOME)/.Garmin/ConnectIQ/Sdks/current
MONKEYC := $(SDK_HOME)/bin/monkeyc
MONKEYDO := $(SDK_HOME)/bin/monkeydo
SIMULATOR := $(SDK_HOME)/bin/connectiq
DEV_KEY := $(HOME)/.Garmin/developer_key

DEVICE ?= edge540
OUT := bin/RowEdge.prg
JUNGLE := monkey.jungle

# Font generation: A=hero 80, B=medium full-width 55, C=grid tall 38, D=grid small 26
TTF := $(HOME)/.Garmin/ConnectIQ/Fonts/RobotoCondensed-Bold.ttf
FA_SIZE := 80
FB_SIZE := 55
FC_SIZE := 38
FD_SIZE := 26
FONT_DIR := resources/fonts

SOURCES := $(wildcard source/*.mc)
RESOURCES := $(wildcard resources/*/*.xml) $(wildcard resources/*/*.png) $(wildcard resources/*/*.fnt)

# Mount point for Garmin Edge USB mass storage
GARMIN_MNT ?= $(wildcard /media/$(USER)/GARMIN)
ifeq ($(GARMIN_MNT),)
GARMIN_MNT := $(wildcard /run/media/$(USER)/GARMIN)
endif

.PHONY: build fonts run_simulator simulator deploy clean

build: $(OUT)

$(OUT): $(SOURCES) $(RESOURCES) $(JUNGLE) manifest.xml
	@mkdir -p bin
	$(MONKEYC) -d $(DEVICE) -f $(JUNGLE) -o $(OUT) -y $(DEV_KEY) -w

fonts:
	python3 tools/gen_font.py $(TTF) $(FA_SIZE) $(FONT_DIR)/font_a
	python3 tools/gen_font.py $(TTF) $(FB_SIZE) $(FONT_DIR)/font_b
	python3 tools/gen_font.py $(TTF) $(FC_SIZE) $(FONT_DIR)/font_c
	python3 tools/gen_font.py $(TTF) $(FD_SIZE) $(FONT_DIR)/font_d

simulator:
	$(SIMULATOR) &
	@sleep 2

run_simulator: build simulator
	$(MONKEYDO) $(OUT) $(DEVICE)

deploy: build
ifeq ($(GARMIN_MNT),)
	$(error Garmin device not found. Connect Edge via USB and retry, or set GARMIN_MNT=/path/to/mount)
endif
	cp $(OUT) $(GARMIN_MNT)/GARMIN/APPS/
	@echo "Deployed to $(GARMIN_MNT)/GARMIN/APPS/ -- eject device and restart Edge"

clean:
	rm -rf bin
