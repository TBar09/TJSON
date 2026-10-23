# TJSON Improved - Examples

Here are some examples on how to use the library in multiple use cases. 

Do note that the code blocks only show the most prominent parts of the program's code and may not correctly work if directly copy-pasted into something like try.haxe.org without some editing.

## Basics

Simple parsing:
```haxe
var myJSONString:String = '
{
	/* This is a JSON file */
	"myStr": "Hello\nnew line\nworld!!",
	"myArr": ["Hello", "World", "!!"],
	"basic types": { // Yup, nested
		"myFloat": 101.214,
		"myInt"	10,
		"myBool" true
	}
}
';

var result:Dynamic = tjson.TJSON.parse(myJSONString);

trace(result.myArr.join(" ")); // "Hello World !!"
trace(Reflect.field(Reflect.field(result, "basic types"), "myFloat")); // 101.214
```

Simple printing:
```haxe
var obj:Dynamic = {
	myStr: "Hello world!!",
	myArr: [10, 20, 30],
	myMap: (["uno" => 1, "dos" => 2] : Map<String, Dynamic>),
	myObj: {
		myInt: 10,
		myBool: true
	}
}

// First we try regular printing
var result:String = tjson.TJSON.encode(obj, SIMPLE);

/*
{"myStr":"Hello world!!","myArr":[10,20,30],"myMap":{"uno":1,"dos":2},"myObj":{"myInt":10,"myBool":true}}
*/
trace(result);

// Now pretty printing
result = tjson.TJSON.encode(obj, FANCY);

/*
{
	"myStr": "Hello world!!",
	"myArr": [10, 20, 30],
	"myMap": {
		"uno": 1,
		"dos": 2
	},
	"myObj": {
		"myInt": 10,
		"myBool": true
	}
}
*/
trace(result);
```

Unserializing an array example:
```haxe
var result:Dynamic = tjson.TJSON.parse('[10, 20, 30]');
trace(result[0]); // 20
```

## Features

Class printing & parsing example:
```haxe
class MyClass {
	public var name:String;
	public var age:Int;

	public function new(name:String, ?age:Int = 20) {
		this.name = name;
		this.age = age;
	}
}

var obj = {
	myCls: new MyClass("Jason", 25),
	myOtherCls: new MyClass("Mike")
}

var myJSONString:String = tjson.TJSON.encode(obj, FANCY);

/*
{
	"myCls": {
		"_hxcls": "MyClass",
		"name": "Jason",
		"age": 25
	},
	"myOtherCls": {
		"_hxcls": "MyClass",
		"name": "Mike",
		"age": 20
	}
}
*/
trace(myJSONString);

var result:Dynamic = tjson.TJSON.parse(myJSONString);
trace(result.myCls.age); // 25
trace(result.myOtherCls.name); // Mike
```


`TJ_noEncode` example:
```haxe
class MyClass {
	public var name:String;
	public var age:Int;

	public function new(name:String, ?age:Int = 20) {
		this.name = name;
		this.age = age;
	}

	public static function TJ_noEncode():Array<String>{
		return ['age']; // Don't include the `age` field when encoded in a JSON.
	}
}

var result:String = tjson.TJSON.encode({myCls: new MyClass("Jason", 25)}, FANCY);

/*
{
	"myCls": {
		"_hxcls": "MyClass",
		"name": "Jason"
	}
}
*/
trace(result);
```

`TJ_unserialize` example:
```haxe
class MyClass {
	public var name:String;
	public var age:Int;

	public function new(name:String, ?age:Int = 20) {
		this.name = name;
		this.age = age;
	}

	public static function TJ_unserialize() {
		trace("I have been unserialized!!");
	}
}

var myJSONString:String = '{"myCls": {"_hxcls": "MyClass", "name": "Jason", "age": 25}}';

/* 
This traces "I have been unserialized!!" when ran, since
MyClass has a static function `TJ_unserialize` that is called.
*/
var result:Dynamic = tjson.TJSON.parse(myJSONString);
```

Enum printing & parsing example:
```haxe
enum Vehicle {
	CAR;
	BICYCLE;
	TRUCK;
	CUSTOM(name:String, mph:Int, isCool:Bool);
}

var obj = {
	myEnm: Vehicle.TRUCK,
	myOtherEnm: Vehicle.CUSTOM("My Custom Car", 245, true)
}

var myJSONString:String = tjson.TJSON.encode(obj, FANCY);

/*
{
	"myEnm": {
		"_hxenm": "Vehicle",
		"name": "TRUCK"
	},
	"myOtherEnm": {
		"_hxenm": "Vehicle",
		"name": "CUSTOM",
		"arguments": ["My Custom Car", 245, true]
	}
}
*/
trace(myJSONString);

var result:Dynamic = tjson.TJSON.parse(myJSONString);
trace(result.myEnm); // TRUCK
trace(result.myOtherEnm); // CUSTOM("My Custom Car",245,true)
```

Unicode string (`\u`) example:
```haxe
var myJSONString:String = '
{
	"myUnicodeStr": "\\u0410\\u0411\\u0412\\u0413\\u0414 \\u0430\\u0431\\u0432\\u0433\\u0434"
}
';

var result:Dynamic = tjson.TJSON.parse(myJSONString);
trace(result.myUnicodeStr); // АБВГД абвгд
```

---