("linux/videodev2.h")


#.`((:integer ioc-s-fmt "VIDIOC_S_FMT")
    (:integer ioc-dqbuf "VIDIOC_DQBUF")
    (:integer ioc-qbuf "VIDIOC_QBUF")
    (:integer ioc-streamoff "VIDIOC_STREAMOFF")
    (:integer ioc-streamon "VIDIOC_STREAMON")
    (:integer ioc-reqbufs "VIDIOC_REQBUFS")
    (:integer ioc-querybuf "VIDIOC_QUERYBUF")
    ,@(loop for i in '("RGB32" "BGR32" "RGB24" "BGR24"
		       "GREY" "YUYV" "UYVY" "YUV422P")
	 collect
	   `(:integer ,(intern i) 
		      ,(concatenate 'string "V4L2_PIX_FMT_" i)))
    (:type u32 "__u32")
    (:type u8 "__u8")
    (:enum buf-type ((video-capture "V4L2_BUF_TYPE_VIDEO_CAPTURE")
		     (video-output "V4L2_BUF_TYPE_VIDEO_OUTPUT")))
    (:enum memory ((memory-mmap "V4L2_MEMORY_MMAP")
		   (memory-user-pointer "V4L2_MEMORY_USERPTR")
		   (memory-overlay "V4L2_MEMORY_OVERLAY")))
    (:structure request-buffers ("struct v4l2_requestbuffers"
				 (u32 count "__u32" "count")
				 (buf-type type "enum v4l2_buf_type" "type")
				 (memory memory "enum v4l2_memory" "memory")))
    (:structure buffer ("struct v4l2_buffer"
			,@(loop for i in '("index" "bytesused" "flags" "sequence"
					   "length") collect
			       `(u32 ,(intern (string-upcase i)) "__u32" ,i))))
    (:structure pix-format 
		("struct v4l2_pix_format"
		 ,@(loop for i in '("width" "height" "pixelformat" 
				    "bytesperline" "sizeimage")
		      collect
			`(u32 ,(intern (string-upcase i)) "__u32" ,i))))
    (:structure format ("struct v4l2_format"
			(buf-type type "v4l2_buf_type" "type")
			(pix-format pix "v4l2_pix_format" "fmt.pix"))))