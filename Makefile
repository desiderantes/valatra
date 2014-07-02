VALAC := valac
FLAGS := 
PKG := --pkg gio-2.0
SRC := $(shell find 'app/' -type f -name "*.vala")
SRC_LIB := $(shell find 'valatra/' -type f -name "*.vala")
LIB := valatra/valatra-1
EXE := app/app
LIB_STATIC_EXT :=

CPKGS := $(shell pkg-config --cflags --libs gio-2.0 glib-2.0 gobject-2.0)

CC := gcc
AR := ar

ifeq ($(OS),Windows_NT)
	LIB_STATIC_EXT := lib
else
	LIB_STATIC_EXT := a
endif

all: $(LIB).$(LIB_STATIC_EXT) $(EXE)

$(LIB).$(LIB_STATIC_EXT): $(LIB).stamp
	$(foreach CSRC,$(SRC_LIB:.vala=), $(shell $(CC) -c $(CSRC).c -o $(CSRC).o -fPIC $(CPKGS)))
	$(AR) rcs $@ $(SRC_LIB:.vala=.o)

$(LIB).stamp: $(SRC_LIB)
	$(VALAC) $(FLAGS) -C -b valatra --library $(LIB) -H $(LIB).h $(SRC_LIB) $(PKG)
	touch $(LIB).stamp
	
$(EXE): $(SRC) $(LIB).$(LIB_STATIC_EXT)
	$(VALAC) $(FLAGS) -C -b app $(SRC) --vapidir=valatra --pkg valatra-1 $(PKG)
	$(CC) -static -o $@ $(SRC:.vala=.c) -Ivalatra -Lvalatra -lvalatra-1 $(CPKGS) 

debug:
	@$(MAKE) "FLAGS=$(FLAGS) -g"

genc:
	@$(MAKE) "FLAGS=$(FLAGS) -C"

clean:
	rm -f valatra/*.c valatra/*.o valatra/*.stamp valatra/*.o.stamp $(LIB).$(LIB_STATIC_EXT) $(LIB).vapi $(LIB).h
	rm -f $(EXE) $(EXE).exe app/*.c app/*.o
	
.PHONY= all clean

