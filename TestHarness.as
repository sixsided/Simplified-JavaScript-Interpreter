package org.sixsided.scripting.SJS
{
  	import flash.display.Sprite;
  	import org.sixsided.scripting.SJS.TestSpec;
    //import org.sixsided.scripting.SJS.*;


    public class TestHarness extends Sprite
    {
        public function TestHarness()
        {
          trace("-------------- SJS TestHarness [" + ((new Date()).toString()) + "] --------------");
          var ts:TestSpec = new TestSpec();
          ts.run_specs();
            //super();
            //      
            //this.addEventListener(FlexEvent.APPLICATION_COMPLETE, init); 
        }
        //private function init(eventObj:FlexEvent):void
        //{
        //    //var btn:Button = new Button();
        //    //btn.label = "hello flex";
        //    //this.addChild(btn);
        //    //trace("Main.as init");
        //    //runScript.btn.addEventListener(FlexEvent.CLICK, function(){
        //    //  trace('button clicked');
        //    //});
        //}
        
        public function evalScript():void{
          trace('evalScript called');
        }
    }
}
