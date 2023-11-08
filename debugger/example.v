import io

struct User {
mut:
	age       int
	name      string
	last_name string
}

type Expr = User | bool | int | string

fn foo(a int, user User, reader io.Reader) {
	println(1)
	println(reader)
	mut arr := [1, 2, 3]
	expr := Expr('string_expr')
	println(expr)
	opt := ?int(3)
	println(opt)
	arr << 7778
	arr2 := ['hello', 'world', '!']
	mut user2 := user
	user2.name = 'Alex'
	bool_true := true
	bool_false := false
	str2 := 'foobar'
	println(arr)
	str := 'hello'
	println('foo')
	x := a + 3
	println(x)
}

struct MyReader {}

fn (r MyReader) read(mut buf []u8) !int {
	return 0
}

fn main() {
	reader := MyReader{}
	user := User{
		age: 23
		name: 'Bob'
		last_name: 'Peterson'
	}
	foo(4, user, reader)
}

// fn fooo(mut a int) {}
