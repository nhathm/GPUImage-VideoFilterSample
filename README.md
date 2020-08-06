# GPUImage-Video-Filter
This project is a sample of using GPUImage to filter and export filtered video.

# Note from owner

I tried to filter video and export filtered video with GPUImage to 'reuse' GPUImage's filters but:

- GPUImage only have good result if use just filter images.
- Have many issue when play/pause/seek video because GPUImage use thread and AVAssetReader to read video buffer, caused bad performance and buggy.
- If you still want to use GPUImage? Try GPUImage3, which using Metal instead of OpenGL
- Using GPUImage2 library from here: https://github.com/techover-io/GPUImage2

- My recommend: use AVFoundation and CoreImage to filter video. Which have good performance and easy to control anything you do. You can easy re-use GPUImage3's filters.
Keywords:
  - Using AVFoundation framework
  - Using AVComposition to create preview video
  - Using AVVideoCompositionInstructionProtocol to 'tell' video compositor how to filter each frame of your video
  - AVVideoCompositing protocol will call for each frame of your video, you can do whatever you want with each frame and return final frame, which filtered, resized, combined...
  - Create your own filters with CoreImage, CIColorKernel and Metal.

#Sample
[Sample](sample.MP4)
