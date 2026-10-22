package;

import tjson.TJSON;

#if (haxe_ver >= 4.2)
import Std.isOfType;
#else
import Std.is as isOfType;
#end

import sys.io.File;

enum TestEnum {
	CAR;
	TRUCK;
	BICYCLE;
	CUSTOM(name:String, mph:Int, isNew:Bool);
}

class ChildClass {
	public var myvar:String;
	public var parent:TestClass;

	public function new(parent:TestClass) {
		this.parent = parent;
		this.myvar = "this works";
	}
}

class TestClass {
	private var priv:String = 'this is private';
	public var pub:String = 'this is public';
	public var subObj:ChildClass;
	public var list:List<String>;
	public var dontSerialize:String = 'this wont be serialized';
    public var unserialized:Bool = false;
    public var aDate:Date;
    public var timestamp:Float;

	public function new() {
		this.subObj = new ChildClass(this);
		this.list = new List();
        this.aDate = Date.now();
        this.timestamp = aDate.getTime();
        //trace('timestamp:' + this.timestamp);
		this.list.push("hello");
	}

	public function test() {
		return "yep";
	}

	public function setPriv(v:String) {
		priv = v;
	}

	public function getPriv() {
		return priv;
	}

	public function TJ_noEncode():Array<String> {
		return ['dontSerialize'];
	}

    public function TJ_unserialize() {
        unserialized = true;
    }
}
//{"priv":"this is private","pub":"this is public","_hxcls":"TestClass"}


class TestParser extends haxe.unit.TestCase {
	public function new() {
		super();
	}

	/**
	 * Test out basic types, including structures with
	 * value, strings, bools, floats & integers, and null.
	 */
	public function testSimple() {
		var result = TJSON.parse("{key:'value'}");
		assertEquals('value', result.key); // Regular string check in structure

		var result = TJSON.parse("[]");
		assertTrue(isOfType(result, Array)); // Type check if array
		assertEquals(0, result.length); // Check Array length

		var result = TJSON.parse("123");
		assertEquals(123, result); // Integer check

		var result = TJSON.parse("123.4");
		assertEquals(123.4, result); // Float check

		var result = TJSON.parse('"123.4"');
		assertEquals("123.4", result); //String check (Shows float but is a string)

		var result = TJSON.parse("true");
		assertEquals(true, result); // Bool (true) check
		var result = TJSON.parse("false");
		assertEquals(false, result); // Bool (false) check

		var result = TJSON.parse("null");
		assertEquals(null, result); // Null check
	}

	/**
	 * Test out more complex features, such as comments, keys with spaces
	 * or without quotations, dangling or no commas, unicode strings, etc.
	 */
	public function testComplex() {
		var data:String = File.getContent("./data/testJson.json");
		var obj = TJSON.parse(data);

		//trace(Std.string(obj));

		assertEquals("value with a 
		newline in the middle!", obj.keyWithNoString.keyWithsinglequote); // String with new line (Structured like this on purpose)

		assertEquals(300, Reflect.field(obj.keyWithNoString, 'k2')); // Key with no quotations surrounding it
		assertEquals("key 3", Reflect.field(obj.keyWithNoString,'key with spaces')); // Key with spaces

		assertEquals(-3.2, obj.arrayWithNoCommaBeforeIt[1]); // Array declared without comma after the last key
		assertEquals(1.0, obj.arrayWithNoCommaBeforeIt[0]); // Same as last
		assertEquals(0.45, obj.arrayWithNoCommaBeforeIt[3]); // Same as last
		assertEquals("aValue2", obj.arrayWithObj[1].key2); // Object inside array
		assertEquals(true, obj.boolValue); // Boolean check
		assertEquals(false, obj.falseValue); // Boolean check

		#if target.unicode
		assertEquals("АБВГД абвгд", obj.utf); // Unicode check (Should fail on Neko since it doesn't natively support it)
		#end
	}

	/**
	 * Test out simple encoding.
	 */
	public function testEncodeObject() {
		var result:String = TJSON.encode({key: 'value', key2: {anotherKey: "another\nValue"}});
		assertEquals('{"key2":{"anotherKey":"another\\nValue"},"key":"value"}', result);
	}

	public function testEncodeArray() {
		var result:String = TJSON.encode([1,2,3,4,[10,10,{myKey:"My\nValue"}]]);
		assertEquals('[1,2,3,4,[10,10,{"myKey":"My\\nValue"}]]', result);
	}
	public function testEncodeMap() {
		var result:String =  TJSON.encode(["key" => ["newKey" => "value"], "key2" => ["anotherKey" => "another\nValue"]]);
		assertEquals('{"key":{"newKey":"value"},"key2":{"anotherKey":"another\\nValue"}}', result);
	}

	public function testEncodeList() {
		var list:List<Dynamic> = new List<Dynamic>();

		list.add("test");
		list.add({key: 'myObject', intval: 31});
		list.add([1, 2, 3, 4]);

		var sublist:List<Dynamic> = new List<Dynamic>();

		sublist.add(1);
		sublist.add("two");
		sublist.add(new List<Dynamic>());
		list.add(sublist);

		assertEquals('["test",{"key":"myObject","intval":31},[1,2,3,4],[1,"two",[]]]', TJSON.encode(list));
	}

	public function testFullCircleObject() {
		var origObj = {
			'1': 'a',
			'2': 'b',
			anArray: [
				{
					objectKey: 'objectValue',
					anotherKey: 'anotherValue'
				}
			],
			anotherArray: [
				"this is a string in a sub array",
				"next will be a float"
			]
		};

		//test simple style
		var jsonString:String = TJSON.encode(origObj);
		var generatedObj:Dynamic = TJSON.parse(jsonString);

		assertEquals('a', Reflect.field(generatedObj, '1'));
		assertEquals('anotherValue', Reflect.field(Reflect.field(generatedObj, 'anArray')[0], 'anotherKey'));

		//test fancy style
		var jsonString:String = TJSON.encode(origObj, FANCY);
		var generatedObj:Dynamic = TJSON.parse(jsonString);

		assertEquals('a', Reflect.field(generatedObj, '1'));
		assertEquals('anotherValue', Reflect.field(Reflect.field(generatedObj, 'anArray')[0], 'anotherKey'));
	}

	public function testCrazyCharacters() {
		var origObj = {
			"str": "!@#$%^&*()_+\"'/.,\\;':{}"
		}

		var jsonString:String = TJSON.encode(origObj);
		var generatedObj:Dynamic = TJSON.parse(jsonString);
		assertEquals(origObj.str, generatedObj.str);
	}

	public function testUtf8Chars() {
		#if target.unicode
		var s:String = '{"str":"\\u0410\\u0411\\u0412\\u0413\\u0414 \\u0430\\u0431\\u0432\\u0433\\u0434"}';
		var obj:Dynamic = TJSON.parse(s);

		assertEquals(obj.str, "АБВГД абвгд");
		#else
		assertEquals(1, 1);
		#end
	}

    public function testInt() {
    	var intStr:String = '{"v": 500}';
    	var obj:Dynamic = TJSON.parse(intStr);

    	assertEquals(500, obj.v);
    	assertTrue(isOfType(obj.v, Int));


    	var intStr:String = "{v:2147483647}";
    	var obj:Dynamic = TJSON.parse(intStr);

    	assertEquals(2147483647, obj.v);
    	assertTrue(isOfType(obj.v, Int));


    	var intStr:String = '{"v": -2147483648}';
    	var obj:Dynamic = TJSON.parse(intStr);

    	assertEquals(-2147483648, obj.v);
    	assertTrue(isOfType(obj.v, Int));


    	var intStr:String = '{"v":5000000000}';
    	var obj:Dynamic = TJSON.parse(intStr);

    	assertEquals(5000000000.0, obj.v);
    	assertTrue(isOfType(obj.v, Float));


    	var intStr:String = "{v:-5000000000}";
    	var obj:Dynamic = TJSON.parse(intStr);

    	assertEquals(-5000000000.0, obj.v);
    	assertTrue(isOfType(obj.v, Float));
    }

	public function testChars() {
		var data:String = File.getContent('./data/chars.json');
		var d:Dynamic = TJSON.parse(data);

		//just making sure it parses without errors
		assertEquals(1, 1);
	}

	public function testFullCircle2() {
		var test = tjson.TJSON.parse('{
			object : customer,
			created : 1378868740,
			id: cus_2YAHJPoReA8KA8,
			"livemode" : false,
			description : test,
			email : null,
			"[":"a quoted string"
			"{":"A multiline
					string"
		}');

		var string1:String = tjson.TJSON.encode(test);
		var data:Dynamic = tjson.TJSON.parse(string1);
		var string2:String = TJSON.encode(data);

		assertEquals(string1, string2);
	}

	public function testNull() {
		var obj:Dynamic = {"nullVal": null, 'non-null': 'null', "array": [null, 1]};
		var data:String = TJSON.encode(obj);
		assertEquals('{"non-null":"null","nullVal":null,"array":[null,1]}', data);

		var obj2:Dynamic = TJSON.parse('{"nullVal":null ,"non-null":"null","array":[null, 1]}');
		var data2:String = TJSON.encode(obj2);
		assertEquals('{"non-null":"null","nullVal":null,"array":[null,1]}', data2);
	}

	public function testClassObject() {
		var obj:TestClass = new TestClass();
		obj.setPriv("this works");

		// Serialize class object
		var json:String = TJSON.encode(obj);
		// trace(json);

		// Unserialize class object
		var ob2:TestClass = TJSON.parse(json);

		assertEquals("yep", ob2.test());
		assertEquals(obj.getPriv(), ob2.getPriv());


		// Confirm that they are seperate instances
		obj.setPriv('newString');
		assertFalse(obj.getPriv() == ob2.getPriv());
		assertEquals("this works", obj.subObj.myvar);
		assertEquals(ob2, ob2.subObj.parent);

        // Test Date object serialization/unserialization
		// Edit: This is no longer supported
		/*
        assertTrue(ob2.aDate != null);
        assertEquals(isOfType(ob2.aDate, Date),true);
        assertEquals(ob2.timestamp, obj.timestamp);
        assertEquals(ob2.aDate.getTime(),obj.timestamp);
		*/


        // Confirm that `TJ_unserialize` was called
        assertEquals(true, ob2.unserialized);

        // Test `TJ_noEncode`
        assertEquals("this wont be serialized", obj.dontSerialize);
        assertEquals(null, ob2.dontSerialize);
	}

	public function testEnumObject() {
		var obj:TestEnum = CUSTOM("My Custom Car", 256, true);

		// Serialize enum object
		var json:String = TJSON.encode({enm: obj});
		// trace(json);

		// Unserialize enum object
		var ob2:Dynamic = TJSON.parse(json);

		assertTrue(Type.enumEq(CUSTOM("My Custom Car", 256, true), ob2.enm));
	}

	public function testObjectReferences() {
		var arr:Array<TestClass> = new Array();
		var ob1:TestClass = new TestClass();

		arr.push(new TestClass());
		arr.push(new TestClass());
		arr.push(ob1);
		arr.push(new TestClass());

		arr.push(ob1);
		arr.push(new TestClass());

		var json:String = TJSON.encode(arr);
		// trace(json);

		var res:Dynamic = TJSON.parse(json);
		assertEquals(res[4], res[2]);
	}
	
}
