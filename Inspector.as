package org.sixsided.scripting.SJS {
  import flash.display.DisplayObjectContainer;
  import flash.display.DisplayObject;
  import flash.utils.getQualifiedClassName;
  
  public class Inspector { 
    
    public static function jsonify(obj:*):String {
      return Inspector.inspect(obj, false);
    }
     
    public static function keys(o:*):Array {
      var k:Array = [];
      var i:*;
      for(i in o) { k.push(i); }
      return k;
    }     
    
    public static function keys_str(o:*):String {
      return Inspector.keys(o).join(", ");
    }
    
    public static  function inspect(obj:*, _opts:Object=null):String {
      var ESC:String = String.fromCharCode(27) + '[';
      var ansi:Object = { 'highlight': ESC + '40;37m', 'normal': ESC + '0m', depth:[
        ESC + '0m',
        ESC + '1;36m',
        ESC + '1;34m',
        ESC + '1;32m',
        ESC + '1;35m',
        ESC + '1;31m',
      ]};
      var opts:Object = { multiline:false, separator:', ', ansi:false };
      var optkey:String;
      if(_opts) { for (optkey in _opts) { opts[optkey] = _opts[optkey]; } }
      
      if(null == obj) return '*null*';
          
      var depth:int = 0;
      var whitespace:String = "                                                                                                ";
      function whitepad():void {
        if(opts.multiline) out += "\n" + whitespace.substr(0, depth*4)
      }
      var obj_stack:Array = [];
      var key_stack:Array = [Inspector.keys(obj)];
      var seen:Array = [obj];
      var out:String = (obj is Array)  ? '[' : '{';
      
      if(typeof(obj) != 'object') return obj;
      
      obj_stack.push(obj);
      
      while(obj_stack.length){
        whitepad();
        var o:* = obj_stack[0];
      
        // Possible improvement: spit out toString of object
        
        // is it a for/in iterable object, typically {} ?  Do we have keys left?
        if(key_stack[0].length) {
          var k:* = key_stack[0].shift();
          if(!(o is Array)) out += k + ':'; 
          
          var classname:String = getQualifiedClassName(o[k]).split('::').pop();   // returns path.to.package::Class         
          if(classname == 'Object' || classname == 'Array') {
            depth++;
            if(opts.ansi) out += ansi.depth[depth]; //x
            if(seen.indexOf(o[k]) != -1) { out += '*recursion*'; continue; }
            seen.push(o[k]);
            key_stack.unshift(Inspector.keys(o[k]));
            obj_stack.unshift(o[k]);
            //out += ansi.highlight; //x
            out += o[k] is Array ? ' [' : ' {';
            //out += ansi.normal; //x
          } else {
            out += o[k];
            if(key_stack[0].length) out += opts.separator;
          }
        } else { // out of keys
          depth--;
          //out += ansi.highlight; //x
          out += o is Array ? ' ] ' : ' } ';
          //out += ansi.normal; //x
          if(opts.ansi) out += ansi.depth[depth];
          key_stack.shift();
          obj_stack.shift();
        }
      
      }
      return out;
    }
    
    public static function inspectDisplayObject(dob:DisplayObject):String{
      var indentStr:String = '  ';
      function ido_r(dob:*, indentation:String = ''):String {
        var out:String = getQualifiedClassName(dob) + " @ " + dob.x + ", " + dob.y + " ( " + dob.width + " x " + dob.height + " )";
        if(dob is DisplayObjectContainer) {         
          for(var i:int = 0; i < dob.numChildren; i++) {
            out += "\n" + indentation + ido_r(dob.getChildAt(i), indentation + indentStr);
          }
        }
        return out;
      }
      return ido_r(dob)
    }
    
    // does the tree 'value' contain all the leaves in the tree 'pattern'?
     public static function structureContains(value:*, pattern:*):Boolean {
      function haz_r(a:*, exp:*):Boolean {
        //scalar?
        if (typeof(exp) != 'object') {
          return a == exp;
        }
        //complex:
        var match:Boolean = true;
        for (var i:* in exp) {
          match = match && a.hasOwnProperty(i) && haz_r(a[i], exp[i]);
        }
        return match;
      }
      return haz_r(value,pattern);
    }
    
     public static function structureMatch(a:*, b:*):Boolean {
       return Inspector.structureContains(a, b) && Inspector.structureContains(b, a);
     }

  }///class
}//pkg
