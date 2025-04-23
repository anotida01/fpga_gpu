# Makefile
CC := gcc
CFLAGS := -Wall -g -std=c99 # Add common compiler flags
SRC := obj_loader.c
OBJ := $(SRC:.c=.o) # Create object file names based on source file names
TARGET := obj_loader # Name of the executable

all: $(TARGET)

$(TARGET): $(OBJ)
	$(CC) $(CFLAGS) $(OBJ) -o $(TARGET) # Linking step

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJ) $(TARGET)