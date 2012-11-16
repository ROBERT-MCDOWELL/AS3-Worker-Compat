package
{

  import flash.display.Bitmap;
  import flash.display.BitmapData;
  import flash.display.Loader;
  import flash.display.Shape;
  import flash.display.Sprite;
  import flash.events.Event;
  import flash.system.Capabilities;
  import flash.text.TextField;
  import flash.utils.getTimer;
  import flash.utils.setTimeout;
  import flash.utils.ByteArray;
  import flash.utils.getDefinitionByName;

  import com.lilcodemonkey.workers.WorkerCompat;
  import com.lilcodemonkey.workers.XTSharedObject;
  import com.lilcodemonkey.workers.AsyncScheduler;

  /**
   * This test uses the AS3-Worker-Compat library to encode JPEGs in an
   * asynchronous manner.  The JPEGEncoder.as class is the standard Adobe
   * library but an added encode_async() method (compare it to the standard
   * encode method.)  It uses AsyncScheduler to break the algorithm into
   * a pseudo-threaded one, which is necessary for single-threaded scenarios,
   * but helpful in multi-threaded players also (synchronous encoding would
   * block the background thread, possibly delaying other jobs that thread
   * is responsible for.)  While asynchronous/scheduled computation is
   * slightly less efficient than synchronous, uninterrupted operation, it
   * allows a thread/Worker to be shared between tasks.
   *
   * Note that the AsyncScheduler is tunable - you can direct how much time
   * it computes each pass, and how much time between passes - and jobs can
   * be submitted with varying priorities (since jobs will compete for CPU
   * time).  Naturally this affects its efficiency of computation compared
   * to synchronous computation, and on a background thread there's no need
   * for time between passes since it doesn't have to render the UI.
   *
   * Also note that while the AsyncScheduler class is static, it is not
   * shared among threads.  There exists a separate instance of it in each
   * Worker thread.
   */
  public class JPEGEncoderTest extends Sprite
  {
    private static const JPEG_QUALITY:int = 50;

    private var shape:Shape;
    private var bitmap:Bitmap;
    private var text:TextField;
    private var log:Array;
    private var header:String;

    private var lastJPEG:Loader;
    private var tgt:Object;

    private var xtSharedObject:Object;

    // Constructor
    public function JPEGEncoderTest():void
    {
      // Get a reference to the cross-thread shared object
      xtSharedObject = new XTSharedObject();

      if (WorkerCompat.workersSupported) {
        // Setup threading
        if (WorkerCompat.Worker.current.isPrimordial) {
          // -- Main thread runs this ----
          doGuiWork();

          var bgWorker:* = WorkerCompat.WorkerDomain.current.createWorker(this.loaderInfo.bytes);
          bgWorker.start();
        } else {
          // -- Background thread runs this ----
          doBackgroundWork();
        }
      } else {
        // Fallback: Do all the work in this thread
        doGuiWork();
        setTimeout(doBackgroundWork, 20);
      }
    }

    private function showInfo():void
    {
      text = new TextField();
      text.width = text.height = 800;
      text.x = 105;
      header =
        "asdf JPEGEncoderTest, AS3-Worker-Compat v0.2.1\n"+
        "Flash Player version: " + Capabilities.version+
        ", workersSupported: "+WorkerCompat.workersSupported+
        ", shareableByteArray support: "+(WorkerCompat.Mutex!=null)+"\n"+
        "------------------------------------------------------------"+
        "------------------------------------------------------------";
      log = [];
      text.text = header + "\nTesting synchronous encoding...";
      addChild(text);
    }

    private function appendLog(msg:String):void
    {
      log.push(msg);
      if (log.length>4) log.shift();

      text.text = header+"\n"+
        (xtSharedObject.msg1 || "--")+"\n"+
        (xtSharedObject.msg2 || "--")+"\n"+
        "------------------------------------------------------------"+
        "------------------------------------------------------------\n"+
        log.join("\n");
    }

    private function doGuiWork():void
    {
      // Setup stage
      stage.align = 'topLeft';
      stage.scaleMode ='noScale';
      stage.frameRate = 60;
      showInfo();

      // Setup shareable bytearray fpr image data
      var imageData:ByteArray = new ByteArray();
      //WorkerCompat.setShareable(imageData);
      xtSharedObject.imageData = imageData;

      // Setup spinner shape graphics
      shape = new Shape();
      bitmap = new Bitmap(new BitmapData(100, 100, false, 0x0));
      addChild(bitmap);

      // Setup JPEG loaders
      lastJPEG = new Loader();
      lastJPEG.y = 200;
      addChild(lastJPEG);

      tgt = { dx:0, dy:0, drotation:0, dscale:1 };

      this.addEventListener(Event.ENTER_FRAME, onFrame);
    }

    private function doBackgroundWork():void
    {
      synchronousEncodingTest();
      xtSharedObject.msg = "BKG: Synchronous tests complete, starting asynchronous encoding";
      asynchronousEncodingTest();
    }

    private function synchronousEncodingTest():void
    {
      var canvas:BitmapData = getRandomBitmapData();
      var ba:ByteArray;

      // Test synchronous encoding with native JPEG encoding BitmapData.encode
      var t0:uint = getTimer();
      ba = tryNativeEncode(canvas);
      if (ba) {
        xtSharedObject.msg1 = "BKG: JPEG generated snychronously using native encoder: "+ba.length+" bytes in "+(getTimer()-t0)+" ms";
      } else {
        xtSharedObject.msg1 = "BKG: can't test synchronous native JPEG encoder (FP < 11.3)";
      }

      // Test synchronous encoding
      t0 = getTimer();
      var j_sync:JPEGEncoder = new JPEGEncoder();
      ba = j_sync.encode(canvas);
      xtSharedObject.msg2 = "BKG: JPEG generated snychronously using JPEGEncoder: "+ba.length+" bytes in "+(getTimer()-t0)+" ms";
    }

    private function asynchronousEncodingTest():void
    {
      var canvas:BitmapData = getRandomBitmapData();

      // Test asynchronous encoding with moderate AsyncScheduler parameters
      //  - will stutter the UI slightly if Workers are not supported
      //  - if workers are supported, this shouldn't affect performance at all
      AsyncScheduler.setParams(150, 15);
      var t0:uint = getTimer();
      var j:JPEGEncoder = new JPEGEncoder(JPEG_QUALITY);

      j.encode_async(canvas, function(ba:ByteArray):void {
        xtSharedObject.msg = "BKG: JPEG generated asynchronously using JPEGEncoder, intensive: "+ba.length+" bytes in "+(getTimer()-t0)+" ms";
        xtSharedObject.imageData = ba;
        xtSharedObject.imageDataValid = true;

        setTimeout(asynchronousEncodingTest, 10);
      }, xtSharedObject.imageData);
    }

    private function getRandomBitmapData(width:int=1024,
                                         height:int=512):BitmapData
    {
      // Generate BMP
      var s:Shape = new Shape();
      for (var i:int=0; i<1000; i++) {
        s.graphics.lineStyle(Math.random()*5, Math.random()*0xffffff);
        s.graphics.moveTo(Math.random()*width, Math.random()*height);
        s.graphics.curveTo(Math.random()*width, Math.random()*height,
                           Math.random()*width, Math.random()*height);
      }
      var canvas:BitmapData = new BitmapData(width, height, false, Math.random()*0xffffff);
      canvas.draw(s);

      return canvas;
    }

    private function onFrame(e:Event):void
    {
      var t:Number = getTimer();

      // Receieve new messages
      var m:String = xtSharedObject.msg;
      if (m) {
        appendLog(m);
        xtSharedObject.msg = null;
      }

      // Apply smoothing
      if (xtSharedObject.smooth && lastJPEG.content) {
        Bitmap(lastJPEG.content).smoothing = true;
        xtSharedObject.smooth = false;
      }

      // Receieve new JPEGs
      var imageData:ByteArray;
      var ba:ByteArray;

      imageData = xtSharedObject.imageData;
      if (xtSharedObject.imageDataValid) {
        // If we don't clone, the image can change as it's overwritten
        lastJPEG.loadBytes(cloneByteArray(imageData));
        xtSharedObject.imageDataValid = false;
        xtSharedObject.smooth = true;
        tgt = { dx:Math.random()*2-1, dy:Math.random()*2-1, drotation:Math.random()*1-0.5, dscale:1+Math.random()*0.004-0.003 };
        lastJPEG.x = 0;
        lastJPEG.y = 200;
        lastJPEG.rotation = 0;
        lastJPEG.scaleX = lastJPEG.scaleY = 1;
      }

      // Animate JPEGs
      lastJPEG.x += tgt.dx;
      lastJPEG.y += tgt.dy;
      lastJPEG.rotation += tgt.drotation;
      lastJPEG.scaleY = lastJPEG.scaleX *= tgt.dscale;

      // Animate spinner
      shape.graphics.clear();
      shape.graphics.beginFill(0x0, 0.05);
      shape.graphics.drawRect(0,0,100,100);
      bitmap.bitmapData.draw(shape);
      shape.graphics.clear();
      shape.graphics.lineStyle(3, 0xff0000, 1, true);
      shape.graphics.drawCircle(50, 50, 46);
      shape.graphics.moveTo(50, 50);
      shape.graphics.lineTo(50+45*Math.cos(t/300), 50+45*Math.sin(t/300));
      bitmap.bitmapData.draw(shape);
    }

    private function tryNativeEncode(canvas:BitmapData):ByteArray
    {
      try {
        var ba:ByteArray = new ByteArray();
        var JPEGEncoderOptionsClass:* = getDefinitionByName("flash.display.JPEGEncoderOptions");
        Object(canvas).encode(canvas.rect, new JPEGEncoderOptionsClass(JPEG_QUALITY), ba);
        return ba;
      } catch (e:Error) { }
      return null;
    }

    private static function cloneByteArray(input:ByteArray):ByteArray
    {
      var ba:ByteArray = new ByteArray();
      input.position = 0;
      ba.writeBytes(input, 0, input.length);
      return ba;
    }

  }
}
