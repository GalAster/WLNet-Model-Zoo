(* ::Package:: *)
(* ::Title:: *)
(*Tools*)
(* ::Subchapter:: *)
(*Introduce*)
NetChain2Graph::usage = "Transform a NetChain to NetGraph.";
ImageEncoder::usage = "";
RemoveLayerShape::usage = "Try to remove the shape of the layer";
MXNet$Bind::usage = "Import and Bind the MX-Symbol and MX-NDArray";
MXNet$Boost::usage = "A Function which call a mxnet evaluation";
(* ::Subchapter:: *)
(*Main*)
(* ::Subsection:: *)
(*Settings*)
Begin["`Tools`"];
Version$Tools = "V0.0";
Updated$Tools = "2018-10-09";
(* ::Subsection::Closed:: *)
(*Codes*)
(* ::Subsubsection:: *)
(*NetChain2Graph*)
NetChain2Graph[other___] := other;
NetChain2Graph[net_NetChain] := Block[
	{nets = Normal@net},
	NetGraph[nets,
		Rule @@@ Partition[Range@Length@nets, 2, 1],
		"Input" -> NetExtract[net, "Input"],
		"Output" -> NetExtract[net, "Output"]
	];
];


(* ::Subsubsection:: *)
(*ImageNetEncoder*)
ImageEncoder[size_ : 224, c_ : "RGB"] := NetEncoder[{
	"Image", size,
	ColorSpace -> c,
	"MeanImage" -> {.485, .456, .406},
	"VarianceImage" -> {.229, .224, .225}^2
}];


(* ::Subsubsection:: *)
(*RemoveLayerShape*)
RemoveLayerShape[layer_ConvolutionLayer] := With[
	{
		k = NetExtract[layer, "OutputChannels"],
		kernelSize = NetExtract[layer, "KernelSize"] ,
		weights = NetExtract[layer, "Weights"],
		biases = NetExtract[layer, "Biases"],
		padding = NetExtract[layer, "PaddingSize"],
		stride = NetExtract[layer, "Stride"],
		dilation = NetExtract[layer, "Dilation"]
	},
	ConvolutionLayer[k, kernelSize,
		"Weights" -> weights, "Biases" -> biases,
		"PaddingSize" -> padding, "Stride" -> stride,
		"Dilation" -> dilation
	]
];
RemoveLayerShape[layer_PoolingLayer] := With[
	{
		f = NetExtract[layer, "Function"],
		kernelSize = NetExtract[layer, "KernelSize"] ,
		padding = NetExtract[layer, "PaddingSize"],
		stride = NetExtract[layer, "Stride"]
	},
	PoolingLayer[kernelSize, stride,
		"PaddingSize" -> padding, "Function" -> f
	]
];
RemoveLayerShape[layer_ElementwiseLayer] := With[
	{f = NetExtract[layer, "Function"]},
	ElementwiseLayer[f]
];
RemoveLayerShape[layer_SoftmaxLayer] := Nothing;
RemoveLayerShape[layer_FlattenLayer] := Nothing;


(* ::Subsubsection:: *)
(*MXNet$Bind*)
MXNet$Bind[pathJ_, pathP_] := Block[
	{symbol, params},
	symbol = MXNetLink`MXSymbolFromJSON@File[pathJ];
	params = MXNetLink`MXModelLoadParameters[pathP];
	<|
		"Framework" -> {"MXNet", Import[pathJ][[-1, -1, -1, -1, -1]]},
		"Graph" -> MXNetLink`MXSymbolToJSON@symbol,
		"Nodes" -> Length@MXNetLink`MXSymbolToJSON[symbol]["nodes"],
		"Put" -> {"Image", "Colorful", "ImageSize"},
		"Get" -> "Image",
		"<<" -> "data",
		">>" -> First@MXNetLink`MXSymbolOutputs@symbol,
		"Weight" -> MXNetLink`NDArrayGetRawArray /@ params["ArgumentArrays"],
		"Auxilliary" -> MXNetLink`NDArrayGetRawArray /@ params["AuxilliaryArrays"],
		"Fixed" -> <||>
	|>
];


(* ::Subsubsection:: *)
(*MXNet$Boost*)
Options[MXNet$Boost] = {TargetDevice -> "GPU"};
MXNet$Boost[dm_Association, OptionsPattern[]] := Block[
	{exe, device, port},
	device = NeuralNetworks`Private`ParseContext@OptionValue[TargetDevice];
	exe = NeuralNetworks`Private`ToNetExecutor[
		NeuralNetworks`NetPlan[<|
			"Symbol" -> MXNetLink`MXSymbolFromJSON@dm["Graph"],
			"WeightArrays" -> dm["Weight"],
			"FixedArrays" -> dm["Fixed"],
			"BatchedArrayDims" -> <|dm["<<"] -> {BatchSize, Sequence @@ Dimensions[#]}|>,
			"ZeroArrays" -> {},
			"AuxilliaryArrays" -> dm["Auxilliary"],
			"Inputs" -> <|"Input" -> dm["<<"]|>,
			"Outputs" -> <|"Output" -> dm[">>"]|>,
			"InputStates" -> <||>,
			"OutputStates" -> <||>,
			"Metrics" -> <||>,
			"LogicalWeights" -> <||>,
			"ReshapeTemplate" -> None,
			"NodeCount" -> dm["nodes"]
		|>],
		1, "Context" -> device, "ArrayCaching" -> True
	];
	port = ToExpression@StringDelete[ToString[exe["Arrays", "Inputs", "Input"]], {"NDArray[", "]"}];
	MXNetLink`NDArray`PackagePrivate`mxWritePackedArrayToNDArrayChecked[#, port];
	NeuralNetworks`NetExecutorForward[exe, False];
	exe["Arrays", "Outputs", "Output"] // MXNetLink`NDArrayGetFlat
]&;


(* ::Subsection:: *)
(*Additional*)
SetAttributes[
	{ },
	{Protected, ReadProtected}
];
End[]
