(* ::Package:: *)

(* ::Subchapter:: *)
(*Import Weights*)


SetDirectory@NotebookDirectory[];
<< NeuralNetworks`
NeuralNetworks`PixelNormalizationLayer;
file = "PixelNorm.m";
def = NeuralNetworks`Private`ReadDefinitionFile[file, "System`"];
NeuralNetworks`DefineLayer["PixelNorm", def];


params = Import@"PGGAN-256 trained on Holo Faces.WXF";


(* ::Subchapter:: *)
(*Pre-defined Structure*)


leakyReLU[alpha_] := ElementwiseLayer[Ramp[#] - alpha * Ramp[-#]&];
$NCHW = TransposeLayer[{1<->4, 2<->3, 3<->4}];
trans = NetGraph[
	<|
		"pad" -> PaddingLayer[{{1, 1}, {1, 1}, {0, 0}, {0, 0}}],
		"t4" -> PartLayer[{2 ;; 5, 2 ;; 5}],
		"t3" -> PartLayer[{1 ;; 4, 2 ;; 5}],
		"t2" -> PartLayer[{2 ;; 5, 1 ;; 4}],
		"t1" -> PartLayer[{1 ;; 4, 1 ;; 4}],
		"add" -> ThreadingLayer[Plus]
	|>,
	{
		NetPort["Input"] -> "pad",
		"pad" -> {"t1", "t2", "t3", "t4"} -> "add",
		"add" -> NetPort["Output"]
	}
];
getCN[name_, s_] := ConvolutionLayer[
	"Weights" -> $NCHW[Normal@params[name <> "/weight"]] / Sqrt@s,
	"Biases" -> params[name <> "/bias"],
	"Stride" -> 1, "PaddingSize" -> 1
];
getDN[name_, s_] := DeconvolutionLayer[
	"Weights" -> $NCHW[trans@Normal@params[name <> "/weight"]] / Sqrt@s,
	"Biases" -> params[name <> "/bias"],
	"Stride" -> 2, "PaddingSize" -> 1
];
getBlock[i_, s1_, s2_] := NetChain[{
	getDN[StringRiffle[{"Gs/", i, "x", i, "/Conv0_up"}, ""], s1],
	leakyReLU[0.2],
	PixelNormalizationLayer[],
	getCN[StringRiffle[{"Gs/", i, "x", i, "/Conv1"}, ""], s2],
	leakyReLU[0.2],
	PixelNormalizationLayer[]
}];


(* ::Subchapter:: *)
(*Main*)


$part1 = NetChain@{
	ReshapeLayer[{512, 4, 4}],
	leakyReLU[0.2],
	PixelNormalizationLayer[],
	getCN["Gs/4x4/Conv", 2304],
	leakyReLU[0.2],
	PixelNormalizationLayer[]
};


mainNet = NetChain[{
	PixelNormalizationLayer[],
	LinearLayer[8192,
		"Weights" -> Transpose[Normal@params["Gs/4x4/Dense/weight"] / 64],
		"Biases" -> Flatten@TransposeLayer[{1<->2}][ConstantArray[Normal@params["Gs/4x4/Dense/bias"], 16]]
	],
	$part1,
	getBlock[8, 2304, 2304],
	getBlock[16, 2304, 2304],
	getBlock[32, 2304, 2304],
	getBlock[64, 2304, 1152],
	getBlock[128, 1152, 576],
	getBlock[256, 576, 288],
	ConvolutionLayer[
		"Weights" -> 2 * $NCHW[Normal@params["Gs/ToRGB_lod1/weight"]] / Sqrt[32],
		"Biases" -> 2 * Normal@params["Gs/ToRGB_lod1/bias"],
		"PaddingSize" -> 0, "Stride" -> 1
	],
	LogisticSigmoid
},
	"Input" -> 512,
	"Output" -> "Image"
]


(* ::Subchapter:: *)
(*Export Model*)


Export["PGGAN-256 trained on Holo Faces.MAT", mainNet, "WXF", PerformanceGoal -> "Speed"]


(* ::Subchapter:: *)
(*Testing*)


SetDirectory@NotebookDirectory[];
mainNet = Import["PGGAN-256 trained on Holo Faces.MAT", "WXF"];


SeedRandom[42];
inBatch = RandomVariate[NormalDistribution[], {200, 512}];
outBatch = mainNet[inBatch, TargetDevice -> "GPU"];
MapIndexed[First@#2 -> #1&, outBatch];


(* ::Code::Initialization::Bold:: *)
pick = {
	1, 2, 3, 5, 6, 7, 8, 9, 21, 22, 27, 28, 30, 32, 33, 36, 37, 38, 39, 40, 41, 43, 44, 47, 48, 54, 55, 56, 58, 59, 63, 64, 66, 67, 68, 69, 70, 71, 74, 75, 76, 77, 78, 79, 80, 82, 83, 84, 85, 87, 88, 89, 90, 91, 92, 96, 97, 99, 100,
	101, 102, 103, 104, 105, 109, 118, 119, 120, 121, 123, 126, 131, 133, 136, 137, 138, 139, 140, 141, 142, 146, 147, 148, 149, 151, 175, 176, 177, 179, 180, 183, 185, 186, 187, 188
};
Export["preview.jpg", ImageCollage[RandomSample[outBatch[[pick]], 25]]]
