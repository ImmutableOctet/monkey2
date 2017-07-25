
Namespace mojo3d.graphics

Private

Class Gltf2Loader

	Method New( asset:Gltf2Asset,dir:String )
		
		_asset=asset
		_dir=dir
	End
	
	Method LoadMesh:Mesh()
		
		Local mesh:=New Mesh
		
		For Local node:=Eachin _asset.scenes[0].nodes
			
			LoadMesh( node,mesh,Null )
		Next
		
		mesh.UpdateTangents()
		
		Return mesh
	End

	Method LoadModel:Model()
		
		Local mesh:=New Mesh
		
		Local materials:=New Stack<Material>
		
		For Local node:=Eachin _asset.scenes[0].nodes
			
			LoadMesh( node,mesh,materials )
		Next
		
		mesh.UpdateTangents()
		
		Local model:=New Model
		
		model.Mesh=mesh
		
		model.Materials=materials.ToArray()
		
		Return model
	End

	Private
	
	Alias IndexType:UInt
	
	Field _asset:Gltf2Asset
	Field _dir:String
	
	Field _data:=New StringMap<DataBuffer>
	Field _textureCache:=New Map<Gltf2Texture,Texture>
	Field _materialCache:=New Map<Gltf2Material,Material>
	
	Method GetData:UByte Ptr( uri:String )
		Local data:=_data[uri]
		If Not data
			data=DataBuffer.Load( _dir+uri )
			_data[uri]=data
		Endif
		Return data.Data
	End
	
	Method GetData:UByte Ptr( buffer:Gltf2Buffer )
		Return GetData( buffer.uri )
	End
	
	Method GetData:UByte Ptr( bufferView:Gltf2BufferView )
		Return GetData( bufferView.buffer )+bufferView.byteOffset
	End
	
	Method GetData:UByte Ptr( accessor:Gltf2Accessor )
		Return GetData( accessor.bufferView )+accessor.byteOffset
	End
	
	Method GetTexture:Texture( texture:Gltf2Texture )
		
		If Not texture Return Null
		
		If _textureCache.Contains( texture ) Return _textureCache[texture]
		
		Local flags:=TextureFlags.Filter|TextureFlags.Mipmap|TextureFlags.WrapS|TextureFlags.WrapT
		
		Local tex:=Texture.Load( _dir+texture.source.uri,flags )
		
		Print "Opened texture:"+_dir+texture.source.uri
		
		_textureCache[texture]=tex
		Return tex
	End
	
	Method GetMaterial:Material( material:Gltf2Material )
		
		If Not material Return New PbrMaterial( Color.Magenta )
		
		If _materialCache.Contains( material ) Return _materialCache[material]
		
		Local mat:=New PbrMaterial
		
		Local texture:=GetTexture( material.baseColorTexture )
		If texture
			mat.ColorTexture=texture
		Endif
		mat.ColorFactor=New Color( material.baseColorFactor.x,material.baseColorFactor.y,material.baseColorFactor.z )
		
		texture=GetTexture( material.emissiveTexture )
		If texture
			mat.EmissiveTexture=texture
			mat.EmissiveFactor=New Color( material.emissiveFactor.x,material.emissiveFactor.y,material.emissiveFactor.z )
		Endif
		
		texture=GetTexture( material.metallicRoughnessTexture )
		If texture
			mat.MetalnessTexture=texture
			mat.RoughnessTexture=texture
		Endif
		mat.MetalnessFactor=material.metallicFactor
		mat.RoughnessFactor=material.roughnessFactor
		
		texture=GetTexture( material.occlusionTexture )
		If texture
			mat.OcclusionTexture=texture
		Endif
		
		texture=GetTexture( material.normalTexture )
		If texture
			mat.NormalTexture=texture
		Endif
			
		_materialCache[material]=mat
		Return mat
	End
	
	Method GetMatrix:Mat4f( node:Gltf2Node )
		
		If node.parent Return GetMatrix( node.parent ) * node.matrix
		
		Return node.matrix
	End
	
	Method LoadMesh( node:Gltf2Node,mesh:Mesh,materials:Stack<Material> )
		
		If node.mesh
			
			Print "mesh="+node.mesh.name
			
			Local matrix:=Cast<AffineMat4f>( GetMatrix( node ) )

			Local cofactor:=matrix.m.Cofactor()
			
			For Local prim:=Eachin node.mesh.primitives
				
				'some sanity checking!
				'
				If prim.mode<>4 Continue
				
				If Not prim.POSITION Or prim.POSITION.componentType<>5126 Or prim.POSITION.type<>"VEC3" DebugStop()
				If Not prim.NORMAL Or prim.NORMAL.componentType<>5126 Or prim.NORMAL.type<>"VEC3" DebugStop()
				If Not prim.TEXCOORD_0 Or prim.TEXCOORD_0.componentType<>5126 Or prim.TEXCOORD_0.type<>"VEC2" DebugStop()
				If Not prim.indices Or (prim.indices.componentType<>5123 And prim.indices.componentType<>5125) Or prim.indices.type<>"SCALAR" DebugStop()
				
				Local pp:=GetData( prim.POSITION )
				Local pstride:=prim.POSITION.bufferView.byteStride
				If Not pstride pstride=12
				
				Local np:=GetData( prim.NORMAL )
				Local nstride:=prim.NORMAL.bufferView.byteStride
				If Not nstride nstride=12
				
				Local tp:=GetData( prim.TEXCOORD_0 )
				Local tstride:=prim.TEXCOORD_0.bufferView.byteStride
				If Not tstride tstride=8
					
				Local vcount:=prim.POSITION.count
				
				Local vertices:=New Vertex3f[vcount],dstvp:=vertices.Data
				
				For Local i:=0 Until vcount
					
					dstvp[i].position=Cast<Vec3f Ptr>( pp )[0]
					dstvp[i].normal=Cast<Vec3f Ptr>( np )[0]
					dstvp[i].texCoord0=Cast<Vec2f Ptr>( tp )[0]
					
					dstvp[i].position.z=-dstvp[i].position.z
					dstvp[i].normal.z=-dstvp[i].normal.z
					
					dstvp[i].position=matrix * dstvp[i].position
					dstvp[i].normal=cofactor * dstvp[i].normal
					
					pp+=pstride
					np+=nstride
					tp+=tstride
				Next
				
				Local icount:=prim.indices.count
				
				Local indices:=New IndexType[icount],dstip:=indices.Data

				Local ip:=GetData( prim.indices )
				Local istride:=prim.indices.bufferView.byteStride
				
				Local v0:=mesh.NumVertices
				
				If prim.indices.componentType=5123
					If Not istride istride=2
					For Local i:=0 Until icount Step 3
						dstip[i+0]=Cast<UShort Ptr>( ip )[0] + v0
						dstip[i+2]=Cast<UShort Ptr>( ip )[1] + v0
						dstip[i+1]=Cast<UShort Ptr>( ip )[2] + v0
						ip+=istride*3
					Next
				Else
					If Not istride istride=4
					For Local i:=0 Until icount Step 3
						dstip[i+0]=Cast<UInt Ptr>( ip )[0] + v0
						dstip[i+2]=Cast<UInt Ptr>( ip )[1] + v0
						dstip[i+1]=Cast<UInt Ptr>( ip )[2] + v0
						ip+=istride*3
					Next
				Endif
				
				If materials And Not mesh.NumVertices mesh.AddMaterials( 1 )				
				
				mesh.AddVertices( vertices )
				
				mesh.AddTriangles( indices,mesh.NumMaterials-1 )
				
				If materials materials.Push( GetMaterial( prim.material ) )
					
				Print "Added "+vcount+" vertices, "+icount+" indices."
				
			Next
			
		Endif
		
		For Local child:=Eachin node.children
			
			LoadMesh( child,mesh,materials )
		Next
		
	End
	
	#rem
	Method AddMeshes( node:Gltf2Node )
		
		If node.mesh
			
			Print "mesh="+node.mesh.name
			
			For Local prim:=Eachin node.mesh.primitives
				
				'some sanity checking!
				'
				If prim.mode<>4 Continue
				
				If Not prim.POSITION Or prim.POSITION.componentType<>5126 Or prim.POSITION.type<>"VEC3" DebugStop()
				If Not prim.NORMAL Or prim.NORMAL.componentType<>5126 Or prim.NORMAL.type<>"VEC3" DebugStop()
				If Not prim.TEXCOORD_0 Or prim.TEXCOORD_0.componentType<>5126 Or prim.TEXCOORD_0.type<>"VEC2" DebugStop()
				If Not prim.indices Or (prim.indices.componentType<>5123 And prim.indices.componentType<>5125) Or prim.indices.type<>"SCALAR" DebugStop()
				
				Local pp:=GetData( prim.POSITION )
				Local pstride:=prim.POSITION.bufferView.byteStride
				If Not pstride pstride=12
				
				Local np:=GetData( prim.NORMAL )
				Local nstride:=prim.NORMAL.bufferView.byteStride
				If Not nstride nstride=12
				
				Local tp:=GetData( prim.TEXCOORD_0 )
				Local tstride:=prim.TEXCOORD_0.bufferView.byteStride
				If Not tstride tstride=8
					
				Local vcount:=prim.POSITION.count
				
				Local vertices:=New Vertex3f[vcount],dstvp:=vertices.Data
				
				For Local i:=0 Until vcount
					dstvp[i].position=Cast<Vec3f Ptr>( pp )[0]
					dstvp[i].normal=Cast<Vec3f Ptr>( np )[0]
					dstvp[i].texCoord0=Cast<Vec2f Ptr>( tp )[0]
					'dstvp[i].position.x=-dstvp[i].position.x
					'dstvp[i].position.y=-dstvp[i].position.y
					dstvp[i].position.z=-dstvp[i].position.z
					dstvp[i].normal.z=-dstvp[i].normal.z
					pp+=pstride
					np+=nstride
					tp+=tstride
				Next
				
				Local icount:=prim.indices.count
				
				Local indices:=New IndexType[icount],dstip:=indices.Data

				Local ip:=GetData( prim.indices )
				Local istride:=prim.indices.bufferView.byteStride
				
				Local v0:=_loadedMesh.NumVertices
				
				If prim.indices.componentType=5123
					If Not istride istride=2
					For Local i:=0 Until icount Step 3
						dstip[i+0]=Cast<UShort Ptr>( ip )[0] + v0
						dstip[i+2]=Cast<UShort Ptr>( ip )[1] + v0
						dstip[i+1]=Cast<UShort Ptr>( ip )[2] + v0
						ip+=istride*3
					Next
				Else
					If Not istride istride=4
					For Local i:=0 Until icount Step 3
						dstip[i+0]=Cast<UInt Ptr>( ip )[0] + v0
						dstip[i+2]=Cast<UInt Ptr>( ip )[1] + v0
						dstip[i+1]=Cast<UInt Ptr>( ip )[2] + v0
						ip+=istride*3
					Next
				Endif
				
				_loadedMesh.AddVertices( vertices )
				
				_loadedMesh.AddTriangles( indices )
					
				_loadedMaterials.Push( GetMaterial( prim.material ) )
				
				Print "Added "+vcount+" vertices, "+icount+" indices."
				
			Next
			
		Endif
		
		For Local child:=Eachin node.children
			
			AddMeshes( child )
		Next
		
	End
	
	#end
	
End

Public

#rem monkeydoc @hidden
#End
Class Gltf2Mojo3dLoader Extends Mojo3dLoader

	Const Instance:=New Gltf2Mojo3dLoader

	Method LoadMesh:Mesh( path:String ) Override
	
		If ExtractExt( path ).ToLower()<>".gltf" Return Null
			
		Local asset:=Gltf2Asset.Load( path )
		If Not asset Return Null
		
		Local loader:=New Gltf2Loader( asset,ExtractDir( path ) )
		Local mesh:=loader.LoadMesh()
		
		Return mesh
	End

	Method LoadModel:Model( path:String ) Override
	
		If ExtractExt( path ).ToLower()<>".gltf" Return Null
			
		Local asset:=Gltf2Asset.Load( path )
		If Not asset Return Null
		
		Local loader:=New Gltf2Loader( asset,ExtractDir( path ) )
		Local mesh:=loader.LoadModel()
		
		Return mesh
	End

	Method LoadBonedModel:Model( path:String ) Override
		
		Return Null
	End

End
