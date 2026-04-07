package main

import "fmt"

func hello() string {
	return "Hello, World!"
}

// main prints a tiny success message so the example has a real runnable binary.
func main() {
	fmt.Println(hello())
}
