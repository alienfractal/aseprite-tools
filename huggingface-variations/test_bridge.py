import base64
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from PIL import Image
from gradio_client import handle_file
import hf_bridge as bridge


def parameter(name, component="Textbox", **extra):
    return {"parameter_name": name, "component": component, **extra}


MODERN = {"parameters": [parameter(name) for name in
    ("images_b64_json", "prompt", "lora_adapter", "seed", "randomize_seed", "guidance_scale", "steps")]}
SDXL = {"parameters": [parameter(n) for n in
    ("prompt", "negative_prompt", "model_name", "width", "height", "steps", "guidance", "seed",
     "mode", "input_image", "resize_mode", "strength", "use_canny", "canny_image")] + [
    parameter("style", type={"items":{"enum":["sai-pixel art","General PixelArt"]}}),
    parameter("param_20", type={"enum":["None","pixel-art-xl-v1.1.safetensors"]}), parameter("param_21")]}
PREFLIGHT = {"parameters": [parameter(n) for n in
    ("model_name", "mode", "input_image", "use_canny", "canny_image", "width", "height", "resize_mode", "strength")] + [
    parameter("param_14"), parameter("param_15"),
    parameter("param_16",parameter_has_default=True,parameter_default="None"),
    parameter("param_17",parameter_has_default=True,parameter_default=0.5)]}
ANIMATION = {"parameters": [parameter("prompt"), parameter("image_path"),
    parameter("canvas",parameter_has_default=True), parameter("duration",parameter_has_default=True),
    parameter("steps",parameter_has_default=True), parameter("seed",parameter_has_default=True),
    parameter("upsample",parameter_has_default=True), parameter("use_lora",parameter_has_default=True),
    parameter("lora",parameter_has_default=True), parameter("frame_count",parameter_has_default=True),
    parameter("last_image_path",parameter_has_default=True)]}
TIMELINE = {"parameters": [parameter("prompt"),parameter("keyframe_1"),parameter("keyframe_2"),
    parameter("action_1"),parameter("keyframe_3",parameter_has_default=True),
    parameter("keyframe_4",parameter_has_default=True),parameter("action_2",parameter_has_default=True),
    parameter("action_3",parameter_has_default=True),parameter("frames_between",parameter_has_default=True),
    parameter("canvas",parameter_has_default=True),parameter("duration",parameter_has_default=True),
    parameter("steps",parameter_has_default=True),parameter("seed",parameter_has_default=True),
    parameter("upsample",parameter_has_default=True),parameter("use_lora",parameter_has_default=True),
    parameter("lora",parameter_has_default=True)]}


class ImmediateJob:
    def __init__(self, value): self.value = value
    def done(self): return True
    def result(self): return self.value


class FakeClient:
    src = "https://owner-test.hf.space/"
    def __init__(self, fail_at=None): self.calls=[];self.fail_at=fail_at
    def view_api(self, **kwargs): return {"named_endpoints": {"/edit_image": MODERN}}
    def submit(self, **kwargs):
        self.calls.append(kwargs)
        if len(self.calls)==self.fail_at: raise RuntimeError("quota exceeded hf_secret_should_be_redacted")
        im=Image.new("RGB",(96,96),(120,130,140));buf=io.BytesIO();im.save(buf,format="PNG")
        return ImmediateJob({"image":"data:image/png;base64,"+base64.b64encode(buf.getvalue()).decode(),
                             "seed":kwargs["seed"],"status":"success"})


class FakeSdxlClient(FakeClient):
    def __init__(self): super().__init__();self.preparations=[]
    def view_api(self,**kwargs): return {"named_endpoints":{"/generate":SDXL,"/fetch_selected_model":PREFLIGHT}}
    def submit(self,**kwargs):
        if kwargs["api_name"]=="/fetch_selected_model":
            self.preparations.append(kwargs);return ImmediateJob(("Model ready",None))
        value=super().submit(**kwargs).result()
        return ImmediateJob((value["image"],{"seed":value["seed"],"mode":"Image to image"}))


class PreparedQwenClient(FakeClient):
    def __init__(self,fail=False): super().__init__();self.prepared=False;self.fail=fail
    def view_api(self,**kwargs): return {"named_endpoints":{"/infer":MODERN,"/prepare_request":MODERN}}
    def submit(self,**kwargs):
        if kwargs['api_name']=='/prepare_request':
            if self.fail: raise RuntimeError('Cloud adapter preparation failed')
            self.prepared=True;return ImmediateJob(tuple(kwargs.values()))
        if not self.prepared: raise RuntimeError('Civitai adapter is not cached')
        return super().submit(**kwargs)


class FakeAnimationClient(FakeClient):
    def __init__(self, folder): super().__init__();self.folder=folder
    def view_api(self,**kwargs): return {"named_endpoints":{"/generate_frames":ANIMATION,"/generate_timeline":TIMELINE}}
    def submit(self,**kwargs):
        self.calls.append(kwargs)
        count=kwargs.get("frame_count",kwargs.get("frames_between",5)+2)
        sheet=Image.new("RGB",(16*count,12),(30,40,50));sheet_path=self.folder/"sheet.png";sheet.save(sheet_path)
        archive=self.folder/"remote-frames.zip"
        with zipfile.ZipFile(archive,"w") as zipped:
            for index in range(count):
                image=Image.new("RGB",(16,12),(index*20,80,120));data=io.BytesIO();image.save(data,format="PNG")
                zipped.writestr(f"frame_{index:02d}.png",data.getvalue())
            data=io.BytesIO();sheet.save(data,format="PNG");zipped.writestr("sheet.png",data.getvalue())
        return ImmediateJob((str(sheet_path),str(archive),"animation report","refined prompt"))


class FakeMageClient(FakeClient):
    def view_api(self,**kwargs): return {"named_endpoints":{"/ask_image":{"parameters":[]}}}
    def submit(self,**kwargs):
        self.calls.append(kwargs)
        return ImmediateJob(("A red-haired pixel-art knight in a green tunic, side view, limited palette.","details"))


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=Path(__file__).parent)
        self.folder=Path(self.temp.name)
        Image.new("RGBA",(16,12),(80,90,100,255)).save(self.folder/"input.png")
        self.cfg={"space":bridge.DEFAULT_SPACE,"account":"test","prompt":"Make a chipped rock",
                  "lora":"Style-Transfer","count":3,"seed":100,"resize":True,"upscale":True}
        self.job=self.folder/"job.json"
    def tearDown(self): self.temp.cleanup()
    def run_case(self,client):
        bridge.atomic_json(self.job,self.cfg)
        with patch.object(bridge,"load_token",return_value="hf_secret_should_be_redacted"):
            bridge.run_job(self.job,lambda *args:(client,handle_file))
        return bridge.read_json(self.folder/"status.json")
    def run_factory(self,factory):
        bridge.atomic_json(self.job,self.cfg)
        with patch.object(bridge,"load_token",return_value="hf_secret_should_be_redacted"):
            bridge.run_job(self.job,factory)
        return bridge.read_json(self.folder/"status.json")
    def test_modern_payload(self):
        args=bridge.make_arguments(MODERN,self.cfg,self.folder/"input.png",13,handle_file)
        self.assertEqual(args["seed"],13)
        self.assertFalse(args["randomize_seed"])
        encoded=json.loads(args["images_b64_json"])[0].split(",",1)[1]
        self.assertEqual(base64.b64decode(encoded),(self.folder/"input.png").read_bytes())
    def test_qwen_prepares_adapter_before_inference(self):
        client=PreparedQwenClient();status=self.run_case(client)
        self.assertEqual(status['state'],'complete',status)
        self.assertTrue(client.prepared)
        self.assertEqual(len(client.calls),3)
    def test_qwen_preparation_failure_never_submits_gpu(self):
        client=PreparedQwenClient(fail=True);status=self.run_case(client)
        self.assertEqual(status['state'],'error')
        self.assertEqual(client.calls,[])
    def test_qwen_prepare_only_never_submits_gpu(self):
        self.cfg['operation']='prepare'
        client=PreparedQwenClient();status=self.run_case(client)
        self.assertEqual(status['state'],'complete',status)
        self.assertTrue(client.prepared);self.assertEqual(client.calls,[])
    def test_gallery_payload(self):
        detail={"parameters":[parameter("images","Gallery"),parameter("prompt")]}
        args=bridge.make_arguments(detail,self.cfg,self.folder/"input.png",2,handle_file)
        self.assertEqual(args["images"][0]["image"]["path"],str(self.folder/"input.png"))
        self.assertIsNone(args["images"][0]["caption"])
    def test_sdxl_image_to_image_payload(self):
        cfg={**self.cfg,"sdxl_style":"sai-pixel art","sdxl_lora":"pixel-art-xl-v1.1.safetensors","strength":0.45,"lora_strength":0.6}
        args=bridge.make_arguments(SDXL,cfg,self.folder/"input.png",9,handle_file)
        self.assertEqual(args["mode"],"Image to image")
        self.assertEqual(args["input_image"]["path"],str(self.folder/"input.png"))
        self.assertEqual((args["width"],args["height"]),(1024,768))
        self.assertEqual(args["style"],["sai-pixel art"])
        self.assertEqual(args["strength"],0.45)
        self.assertEqual(args["param_20"],"pixel-art-xl-v1.1.safetensors")
        self.assertEqual(args["param_21"],0.6)
        self.assertFalse(args["use_canny"]);self.assertIsNone(args["canny_image"])
    def test_sdxl_preflight_slot_mapping(self):
        args=bridge.make_arguments(SDXL,self.cfg,self.folder/"input.png",9,handle_file)
        prep=bridge.make_preflight_arguments(PREFLIGHT,args)
        self.assertEqual(prep["param_14"],"None")
        self.assertEqual(prep["param_15"],0.5)
        self.assertEqual(prep["param_16"],"None")
        self.assertNotIn("param_20",prep)
    def test_sdxl_complete_pipeline(self):
        self.cfg.update(space="lienthealien/RuinedHugg",guidance=7,steps=25,strength=0.45)
        client=FakeSdxlClient();status=self.run_case(client)
        self.assertEqual(status["state"],"complete",status)
        self.assertEqual(len(client.preparations),1)
        self.assertEqual(len(client.calls),3)
        self.assertEqual([f["seed"] for f in status["files"]],[100,101,102])
        for call in client.calls: self.assertEqual(call["mode"],"Image to image")
        self.assertEqual(len({c["input_image"]["path"] for c in client.calls}),1)
    def test_sdxl_invalid_strength_rejected(self):
        with self.assertRaisesRegex(ValueError,"denoising"):
            bridge.make_arguments(SDXL,{**self.cfg,"strength":0},self.folder/"input.png",9,handle_file)
    def test_animation_arguments_include_optional_last_frame(self):
        last=self.folder/"last-input.png";Image.new("RGB",(16,12),(1,2,3)).save(last)
        cfg={"prompt":"character turns","canvas":"960x544 · 16:9 fast","duration":2,"steps":6,
             "seed":42,"upsample":False,"animation_lora":"lightx","frame_count":7}
        args=bridge.make_animation_arguments(ANIMATION,cfg,self.folder/"input.png",last,42,handle_file)
        self.assertEqual(args["image_path"]["path"],str(self.folder/"input.png"))
        self.assertEqual(args["last_image_path"]["path"],str(last))
        self.assertEqual(args["lora"],"lightx");self.assertTrue(args["use_lora"])
        self.assertEqual(args["frame_count"],7)
    def test_animation_pipeline_unpacks_ordered_frames(self):
        Image.new("RGBA",(16,12),(20,30,40,255)).save(self.folder/"last-input.png")
        self.cfg={"operation":"animate","space":"lienthealien/MiniMax-H3-Turbo-Lora-UNCENSORED",
                  "account":"test","endpoint":"/generate_frames","prompt":"character turns",
                  "frame_count":5,"duration":2,"steps":6,"seed":42,"animation_lora":"larry"}
        client=FakeAnimationClient(self.folder);status=self.run_case(client)
        self.assertEqual(status["state"],"complete",status)
        self.assertEqual(len(status["files"]),5)
        self.assertEqual(status["report"],"animation report")
        self.assertIn("last_image_path",client.calls[0])
        for entry in status["files"]:
            with Image.open(entry["path"]) as image:self.assertEqual(image.size,(16,12))
    def test_animation_both_outputs_include_sheet(self):
        self.cfg={"operation":"animate_frames","space":"lienthealien/MiniMax-H3-Turbo-Lora-UNCENSORED",
                  "account":"test","endpoint":"/generate_frames","prompt":"character turns","frame_count":5,
                  "duration":2,"steps":6,"seed":42,"animation_lora":"larry","output_mode":"Both"}
        status=self.run_case(FakeAnimationClient(self.folder))
        self.assertEqual(status["state"],"complete",status);self.assertEqual(len(status["files"]),5)
        self.assertEqual(len(status["sheets"]),1)
        with Image.open(status["sheets"][0]["path"]) as image:self.assertEqual(image.size,(80,12))
    def test_mage_prompt_preview_never_submits_generation(self):
        self.cfg.update(operation="improve_prompt",count=1,vision_space="lienthealien/mage-vl-demo",
                        vision_question="Describe the sprite.",vision_max_tokens=200)
        mage=FakeMageClient();generator=FakeClient()
        def factory(space,token): return (mage if space=="lienthealien/mage-vl-demo" else generator,handle_file)
        status=self.run_factory(factory)
        self.assertEqual(status["state"],"complete",status);self.assertEqual(len(mage.calls),1)
        self.assertEqual(generator.calls,[])
        self.assertIn("red-haired pixel-art knight",status["improved_prompt"])
        self.assertIn("Make a chipped rock",status["improved_prompt"])
        self.assertIn("red-haired pixel-art knight",status["visual_description"])
        self.assertTrue((self.folder/"prompt-details.json").is_file())
    def test_timeline_pipeline_uses_start_end_and_action(self):
        Image.new("RGBA",(16,12),(20,30,40,255)).save(self.folder/"last-input.png")
        self.cfg={"operation":"animate_timeline","space":"lienthealien/MiniMax-H3-Turbo-Lora-UNCENSORED",
                  "account":"test","endpoint":"/generate_timeline","prompt":"same pixel art style",
                  "action_prompt":"raise the sword","frames_between":4,"duration":2,"steps":6,"seed":42,
                  "animation_lora":"larry","output_mode":"Sprite sheet"}
        client=FakeAnimationClient(self.folder);status=self.run_case(client)
        self.assertEqual(status["state"],"complete",status);self.assertEqual(status["files"],[])
        self.assertEqual(len(status["sheets"]),1);self.assertEqual(client.calls[0]["action_1"],"raise the sword")
        self.assertIn("keyframe_1",client.calls[0]);self.assertIn("keyframe_2",client.calls[0])
    def test_cancel_active_remote_job(self):
        class Pending:
            cancelled=False
            def done(self): return False
            def cancel(self): self.cancelled=True
        pending=Pending();(self.folder/"cancel.request").touch()
        with self.assertRaises(bridge.JobCancelled): bridge.wait_for_job(pending,self.folder,lambda *a:None,"Test")
        self.assertTrue(pending.cancelled)
    def test_unknown_required_input_is_rejected(self):
        with self.assertRaisesRegex(ValueError,"Unsupported required"):
            bridge.make_arguments({"parameters":[parameter("new_setting")]},self.cfg,self.folder/"input.png",0,handle_file)
    def test_private_space_style_and_strength(self):
        detail={"parameters": MODERN["parameters"] + [
            parameter("prompt_edit_style",type={"enum":["(No style)","General Pixel Art"]}),
            parameter("lora_strength"),
            parameter("output_resolution",parameter_has_default=True,parameter_default="auto")]}
        self.cfg.update(style="General Pixel Art",lora_strength=0.75)
        args=bridge.make_arguments(detail,self.cfg,self.folder/"input.png",4,handle_file)
        self.assertEqual(args["prompt_edit_style"],"General Pixel Art")
        self.assertEqual(args["lora_strength"],0.75)
        self.assertNotIn("output_resolution",args)
    def test_lora_is_not_silently_chosen(self):
        self.cfg["lora"]=""
        with self.assertRaisesRegex(ValueError,"requires a LoRA"):
            bridge.make_arguments(MODERN,self.cfg,self.folder/"input.png",0,handle_file)
    def test_variations_seeds_original_reference_and_resize(self):
        client=FakeClient();status=self.run_case(client)
        self.assertEqual(status["state"],"complete",status)
        self.assertEqual([c["seed"] for c in client.calls],[100,101,102])
        self.assertEqual(len({c["images_b64_json"] for c in client.calls}),1)
        self.assertEqual(len(status["files"]),3)
        for entry in status["files"]:
            with Image.open(entry["path"]) as im: self.assertEqual(im.size,(16,12))
        self.assertNotIn("hf_secret_should_be_redacted",(self.folder/"status.json").read_text())
    def test_partial_result_and_no_paid_retry(self):
        client=FakeClient(fail_at=2);status=self.run_case(client)
        self.assertEqual(status["state"],"error")
        self.assertEqual(len(status["files"]),1)
        self.assertEqual(len(client.calls),2)
        self.assertNotIn("hf_secret_should_be_redacted",status["message"])
    def test_cancel_prevents_submission(self):
        (self.folder/"cancel.request").touch()
        client=FakeClient();status=self.run_case(client)
        self.assertEqual(status["state"],"cancelled")
        self.assertEqual(len(client.calls),0)
    def test_inspection_never_generates(self):
        self.cfg["operation"]="inspect"
        client=FakeClient();status=self.run_case(client)
        self.assertEqual(status["state"],"complete")
        self.assertEqual(client.calls,[])
        self.assertTrue((self.folder/"api-info.json").is_file())
    def test_palette_does_not_invent_black(self):
        cfg={"match_palette":True,"palette":[[200,50,60],[40,180,80]]}
        image=Image.new("RGBA",(2,2),(0,0,0,128))
        result=bridge.postprocess(image,cfg,(2,2))
        self.assertIn(result.getpixel((0,0))[:3],[(200,50,60),(40,180,80)])
        self.assertEqual(result.getpixel((0,0))[3],128)
    def test_remote_filter_error_is_preserved(self):
        with self.assertRaisesRegex(ValueError,"blocked by Space"):
            bridge.extract_image({"status":"blocked","message":"blocked by Space"})
    def test_reject_external_download(self):
        with self.assertRaisesRegex(ValueError,"outside this Space"):
            bridge.read_result_image("https://other.invalid/image.png",FakeClient(),"hf_test")
    def test_space_url_normalization(self):
        self.assertEqual(bridge.normalize_space("https://huggingface.co/spaces/owner/test/"),"owner/test")
        with self.assertRaises(ValueError): bridge.normalize_space("https://other.invalid/test")
    @unittest.skipUnless(bridge.os.name=="nt","Windows DPAPI")
    def test_token_encryption(self):
        text="hf_nonsecret_test_value"
        encrypted=bridge.protect_token(text)
        self.assertNotIn(text,encrypted)
        self.assertEqual(bridge.protect_token(encrypted,True),text)


if __name__=="__main__": unittest.main(verbosity=2)
