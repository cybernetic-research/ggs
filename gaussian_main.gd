extends Node3D

@export var splat_filename: String = "nuts.ply"

#
#
#	lightning0 implementation
#
#
var num_vertex : int = 0
var splatProperties : Array[String] = []
var splatPoints : Array = []
var splatAsFile : FileAccess
var xPos : int
var yPos : int
var zPos : int
var xScale : int
var yScale : int
var zScale : int
var rot0 : int
var rot1 : int
var rot2 : int
var rot3 : int
var r : int
var g : int
var b : int
var opacity : int
var splatMultiMesh : MultiMesh

#
#
#	haztr0 implementation
#
#
@onready var camera = get_node("Camera")
@onready var screen_texture = get_node("TextureRect")
var rd = RenderingServer.get_rendering_device()
var pipeline: RID
var shader: RID
var blend := RDPipelineColorBlendState.new()
var framebuffer: RID
var vertex_array: RID
var index_array: RID
var static_uniform_set: RID
var dynamic_uniform_set: RID
var clear_color_values := PackedColorArray([Color(0,0,0,0)])
var cull_uniform_set1: RID
var cull_uniform_set2: RID
var num_coeffs = 45
var num_coeffs_per_color = num_coeffs / 3
var sh_degree = sqrt(num_coeffs_per_color + 1) - 1	
var sort_pipeline: RID
var histogram_pipeline: RID
var depth_out_buffer: RID
var histogram_buffer: RID
var depth_uniform
var depth_out_uniform
var histogram_uniform_set0
var histogram_uniform_set1
var radixsort_hist_shader: RID
var radixsort_shader: RID
var globalInvocationSize: int
var cull_buffer: RID
var cull_uniform: RDUniform
var visible_counter_buffer: RID
var visible_counter_uniform: RDUniform
var cull_pipeline: RID
var cull_shader: RID
var visible_count: int = 0
var output_tex: RID
var display_texture:Texture2DRD
var camera_matrices_buffer: RID
var params_buffer: RID
var modifier: float = 1.0
var last_direction := Vector3.ZERO
var last_position := Vector3.ZERO
var vertices: PackedFloat32Array
const NUM_BLOCKS_PER_WORKGROUP = 1024
var NUM_WORKGROUPS

#
#
# intermediate
#
#
var num_properties = 0


func _ready():
	init_lightning0()


func init_lightning0():
	# Create a new MultiMeshInstance3D node
	var multi_mesh_instance = MultiMeshInstance3D.new()
	add_child(multi_mesh_instance)  # Add it to the current node

	# Create and configure the MultiMesh
	splatMultiMesh = MultiMesh.new()
	splatMultiMesh.use_colors = true  # Enable per-instance colors
	splatMultiMesh.transform_format = MultiMesh.TRANSFORM_3D  # Set the transform format

	# Create a new PointMesh
	var point_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0)])  # Single point at origin
	point_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)

	# Assign the PointMesh to the MultiMesh
	splatMultiMesh.mesh = point_mesh

	# Assign the MultiMesh to the MultiMeshInstance3D
	multi_mesh_instance.multimesh = splatMultiMesh

	# Optionally configure other properties of the MultiMeshInstance3D
	multi_mesh_instance.transform = Transform3D.IDENTITY  # Set its transform if needed
	
	# Load the PLY data
	load_ply_data_lightning0(splat_filename)
	# Apply a 180-degree rotation around the Y-axis to the entire MultiMeshInstance3D
	var rotation_y = Transform3D(Basis(Vector3(0, 1, 0), PI))  # 180 degrees around X-axis
	multi_mesh_instance.transform *= rotation_y
	var rotation_z = Transform3D(Basis(Vector3(0, 0, 1), PI))  # 180 degrees around X-axis
	multi_mesh_instance.transform *= rotation_z

func load_ply_data_lightning0(path : String):
	splatMultiMesh.instance_count = 0
	
	splatAsFile = FileAccess.open(path, FileAccess.READ)
	
	num_properties = 0
	var line = splatAsFile.get_line()
	while line != "end_header":
		line = splatAsFile.get_line()
		print(line)
		if line.begins_with("element vertex"):
			num_vertex = int(line.split(" ")[2])
		
		elif line.begins_with("property float "):
			splatProperties.append(line.replace("property float ", ""))
			num_properties += 1

		elif line.begins_with("property"):
			num_properties += 1
		
		elif line.begins_with("end_header"):
			break

	print("num splats: ", num_vertex)
	print("num properties: ", num_properties)

	splatMultiMesh.instance_count = num_vertex
	
	xPos = splatProperties.find("x")
	yPos = splatProperties.find("y")
	zPos = splatProperties.find("z")
	
	xScale = splatProperties.find("scale_0")
	yScale = splatProperties.find("scale_1")
	zScale = splatProperties.find("scale_2")
	
	rot0 = splatProperties.find("rot_0")
	rot1 = splatProperties.find("rot_1")
	rot2 = splatProperties.find("rot_2")
	rot3 = splatProperties.find("rot_3")
	
	r = splatProperties.find("f_dc_0")
	g = splatProperties.find("f_dc_1")
	b = splatProperties.find("f_dc_2")
	
	opacity = splatProperties.find("opacity")
	
	var thread : Thread
	thread = Thread.new()
	thread.start(loadPointAndCreateMesh)


func loadPointAndCreateMesh():
	var count : int = 0
	splatMultiMesh.visible_instance_count = 0
	while count < num_vertex:
		var newSplat : Array[float] = []
		for property in splatProperties:
			newSplat.append(splatAsFile.get_float())
		splatPoints.append(newSplat)
		
		var splatPoint = newSplat
		var splatPointTransform = Transform3D()
		
		splatPointTransform.origin = Vector3(
			splatPoint[xPos] * 5,
			splatPoint[yPos] * 5,
			splatPoint[zPos] * 5
		)
		
		splatPointTransform.basis = splatPointTransform.basis.scaled(
			Vector3(
				splatPoint[xScale],
				splatPoint[yScale],
				splatPoint[zScale]
			)
		)
		
		splatPointTransform.basis = splatPointTransform.basis.rotated(
			Vector3(
				splatPoint[rot0],
				splatPoint[rot1],
				splatPoint[rot2]
			).normalized(),
			splatPoint[rot3]
		)
		
		splatMultiMesh.set_instance_transform(count, splatPointTransform)
		
		splatMultiMesh.set_instance_color(count, 
			Color(
				clamp(splatPoint[r], 0.0, 1.0), 
				clamp(splatPoint[g], 0.0, 1.0), 
				clamp(splatPoint[b], 0.0, 1.0),
				clamp(splatPoint[opacity], 0.0, 1.0)
			)
		)
		
		splatMultiMesh.visible_instance_count += 1
		
		count += 1
		if count % 10000 == 0:
			print(str(round((float(count)/float(num_vertex))*100)) + "%" + " (" + str(count) + "/" + str(num_vertex) + ")")
	
	vertices = splatAsFile.get_buffer(num_vertex * num_properties * 4).to_float32_array()
	splatAsFile.close()
	print("finished")
