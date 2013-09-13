package org.sixsided.scripting {

	public class Promise {
		public static const FULFILLED:int = 1;
		public static const FAILED:int = 2;
		
		
		private var _status:int = 0;
		private var _onFulfilled:Vector.<Function> = new Vector.<Function>;
		private var _onFailed:Vector.<Function> = new Vector.<Function>;
		private var _resolveArgs:Array;
		
		
		// get status
		public function get fulfilled():Boolean {
			return _status == Promise.FULFILLED;
		}
		public function get failed():Boolean {
			return _status == Promise.FAILED;
		}
		
		// set status and trigger handlers
		public function fulfill(...result):void {
			doResultHandler(Promise.FULFILLED, _onFulfilled, result);
		}
		public function fail(...reason):void {
			doResultHandler(Promise.FAILED, _onFailed, reason);
		}

		
		// set handlers
		public function onFulfill(f:Function):Promise {
			setResultHandler(Promise.FULFILLED, f, _onFulfilled);
			return this;
		}
		public function onFail(f:Function):Promise {
			setResultHandler(Promise.FAILED, f, _onFailed);
			return this;
		}
		
		// adapt events
	    /*public function succeedOn(o:EventDispatcher, eventName:String) : Promise {
	      o.addEventListener(eventName, function _el_(e:*, ...ignore) : void {
	        o.removeEventListener(eventName, _el_);
	        fulfill(e.toString());
	      });
	    }
    
	    public function failOn(o:EventDispatcher, eventName:String) : Promise {
	      o.addEventListener(eventName, function _el_(e:*, ...ignore) : void {
	        o.removeEventListener(eventName, _el_);
	        fail(e.toString());
	      });
	    }*/
		
		
		// then:
		// you can chain functions that return promises:
		// doThisFirst().then(doThisSecond).then(doThisThird)
    public function then(cb:Function, eb:Function=null) : Promise {
      var p:Promise = new Promise;
      
      onFulfill(function(v:*=null) : void {
        var result:* = cb(v);
        if(result is Promise) result.onFulfill(p.fulfill).onFail(p.fail); else p.fulfill(result);
      });

      // If we return a failing result as a promise, we're promising the /reason/ for the failure,
      // but not any way to recover from the failure; therefore we don't call
      // onFulfill.
      onFail(function(v:*=null) : void {
        var result:* = (eb != null) ? eb(v) : null;
        if(result is Promise) result.onFail(p.fail); else p.fail(result);
      });

      return p;
    }

		
		//////////////////////////////////////// private
		
		private function setResultHandler(s:int, f:Function, a:Vector.<Function>) : void {
			if(_status == s) 
			  f.apply(null, _resolveArgs); 
			else 
			  a.push(f);
		}

    // ignores multiple resolutions
		private function doResultHandler(s:int, a:Vector.<Function>, resolveArgs:Array) : void {
		  if(_status !== 0) return;
			_status = s;
		  _resolveArgs = resolveArgs;
			while(a.length) a.shift().apply(null, _resolveArgs);
		}
	}
	
}
