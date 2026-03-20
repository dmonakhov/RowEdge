SDK_HOME := $(HOME)/.Garmin/ConnectIQ/Sdks/current
MONKEYC := $(SDK_HOME)/bin/monkeyc
MONKEYDO := $(SDK_HOME)/bin/monkeydo
SIMULATOR := $(SDK_HOME)/bin/connectiq
DEV_KEY := $(HOME)/.Garmin/developer_key

DEVICE ?= edge540
OUT := bin/RowEdge.prg
JUNGLE := monkey.jungle

SOURCES := $(wildcard source/*.mc)
RESOURCES := $(wildcard resources/*/*.xml) $(wildcard resources/*/*.png)

.PHONY: build run_simulator simulator clean

build: $(OUT)

$(OUT): $(SOURCES) $(RESOURCES) $(JUNGLE) manifest.xml
	@mkdir -p bin
	$(MONKEYC) -d $(DEVICE) -f $(JUNGLE) -o $(OUT) -y $(DEV_KEY) -w

simulator:
	$(SIMULATOR) &
	@sleep 2

run_simulator: build simulator
	$(MONKEYDO) $(OUT) $(DEVICE)

clean:
	rm -rf bin
