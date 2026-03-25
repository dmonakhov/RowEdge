SDK_HOME := $(HOME)/.Garmin/ConnectIQ/Sdks/current
MONKEYC := $(SDK_HOME)/bin/monkeyc
MONKEYDO := $(SDK_HOME)/bin/monkeydo
SIMULATOR := $(SDK_HOME)/bin/connectiq
DEV_KEY := $(HOME)/.Garmin/developer_key

DEVICE ?= edge540
OUT := bin/RowEdge.prg
JUNGLE := monkey.jungle

# Font generation from RobotoCondensed-Bold
TTF := $(HOME)/.Garmin/ConnectIQ/Fonts/RobotoCondensed-Bold.ttf

SOURCES := $(wildcard source/*.mc)
RESOURCES := $(wildcard resources/*/*.xml) $(wildcard resources/*/*.png) $(wildcard resources/*/*.fnt) \
             $(wildcard resources-rectangle-*/*/*.xml) $(wildcard resources-rectangle-*/*/*.png) $(wildcard resources-rectangle-*/*/*.fnt)

# Mount point for Garmin Edge USB mass storage
GARMIN_MNT ?= $(wildcard /media/$(USER)/GARMIN)
ifeq ($(GARMIN_MNT),)
GARMIN_MNT := $(wildcard /run/media/$(USER)/GARMIN)
endif

.PHONY: build fonts run_simulator simulator deploy clean

build: $(OUT)

$(OUT): $(SOURCES) $(RESOURCES) $(JUNGLE) manifest.xml
	@mkdir -p bin
	$(MONKEYC) -d $(DEVICE) -f $(JUNGLE) -o $(OUT) -y $(DEV_KEY)

fonts:
	@echo "=== Edge 540/840 (246x322) ==="
	python3 tools/gen_font.py $(TTF) 80 resources/fonts/font_a
	python3 tools/gen_font.py $(TTF) 55 resources/fonts/font_b
	python3 tools/gen_font.py $(TTF) 38 resources/fonts/font_c
	python3 tools/gen_font.py $(TTF) 26 resources/fonts/font_d
	@echo "=== Edge 1040 (282x470) ==="
	python3 tools/gen_font.py $(TTF) 91 resources-rectangle-282x470/fonts/font_a
	python3 tools/gen_font.py $(TTF) 63 resources-rectangle-282x470/fonts/font_b
	python3 tools/gen_font.py $(TTF) 43 resources-rectangle-282x470/fonts/font_c
	python3 tools/gen_font.py $(TTF) 29 resources-rectangle-282x470/fonts/font_d

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
