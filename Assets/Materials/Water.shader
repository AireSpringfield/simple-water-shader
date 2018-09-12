Shader "Custom/Water"
{

	Properties
	{

		[Header(Basic Settings)]
		_UnitPerUV("How Many Units In World Equivalent To One UV Unit", Float) = 100
		_ColSurface("Water Surface Color", Color) = (0.0078, 0.5176, 0.7)
		_ColShore("Shore Color Tint", Color) = (0.0, 0.9, 1.0)
		_ThresDeepest("Deepest If Depth Exceeds This", Range(0.01, 0.99)) = 0.40
		_Smoothness("Color Transition Smoothness", Range(0,10))= 2.0
		_Extinction("Color Extinction Rate Under Water", Range(0.0, 1.0)) = 0.4

		[Header(Wind And Waves)]
		_VecWind("Velocity of Wind (XY)", Vector) = (1, 1, 0, 0)
		_WaveIntensity("Wave Intensity", Range(0.1, 5)) = 1
		_TexNormal("Bump Normal Texture", 2D) = ""{}


		[Header(Directional Light)]
		_DirDirectionalLight("Light Direction", Vector) = (1, -1, 1)
		_ColDirectionalLight("Light Color", Color) = (1, 1, 1)
		_Shininess("Shininess", Range(0, 3)) = 0.12

		[Header(Refraction)]
		_RefrScale("Refraction Scale", Range(0, 5)) = 1

		[Header(Reflection)]
		_R0("Reflection Rate Above Water", Range(0, 1)) = 0.02
		_ReflectionEnv("Reflection Environment Cubemap", Cube) = ""{}

		[Header(Foam)]
		_TexFoam("Foam Texture", 2D) = ""{}
		_FoamDepthMin("Min Depth Foam Appears", Range(0, 1)) = 0.2
		_FoamDepthMax("Max Depth Foam Appears", Range(0, 1)) = 0.5



	}
	SubShader
	{
		Tags { "RenderType"="Transparent" }

		GrabPass{ "_TexRefraction" }





		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			// make fog work
			// #pragma multi_compile_fog
			
			#include "UnityCG.cginc"
			//#include "snoise.cginc"
			//
				// Description : HLSL 2D simplex noise function
				//      Author : Ian McEwan, Ashima Arts
				//  Maintainer : ijm
				//     Lastmod : 20110822 (ijm)
				//     License : 
				//  Copyright (C) 2011 Ashima Arts. All rights reserved.
				//  Distributed under the MIT License. See LICENSE file.
				//  https://github.com/ashima/webgl-noise
				// 

				float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
				float2 mod289(float2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
				float3 permute(float3 x) { return mod289(((x*34.0) + 1.0)*x); }

				float snoise(float2 v)
				{
					// Precompute values for skewed triangular grid
					const float4 C = float4(0.211324865405187,  // (3.0-sqrt(3.0))/6.0
						0.366025403784439,	// 0.5*(sqrt(3.0)-1.0)
						-0.577350269189626, // -1.0 + 2.0 * C.x
						0.024390243902439	// 1.0 / 41.0
						);


					// First corner (x0)
					float2 i = floor(v + dot(v, C.yy));
					float2 x0 = v - i + dot(i, C.xx);

					// Other two corners (x1, x2)
					float2 i1;
					i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
					float2 x1 = x0.xy + C.xx - i1;
					float2 x2 = x0.xy + C.zz;

					// Do some permutations to avoid
					// truncation effects in permutation
					i = mod289(i);
					float3 p = permute(
						permute(i.y + float3(0.0, i1.y, 1.0))
						+ i.x + float3(0.0, i1.x, 1.0));

					float3 m = max(0.5 - float3(
						dot(x0, x0),
						dot(x1, x1),
						dot(x2, x2)
						), 0.0);

					m = m*m;
					m = m*m;

					// Gradients: 
					//  41 pts uniformly over a line, mapped onto a diamond
					//  The ring size 17*17 = 289 is close to a multiple of 41 (41*7 = 287)

					float3 x = 2.0 * frac(p * C.www) - 1.0;
					float3 h = abs(x) - 0.5;
					float3 ox = floor(x + 0.5);
					float3 a0 = x - ox;

					// Normalise gradients implicitly by scaling m
					// Approximation of: m *= inversesqrt(a0*a0 + h*h);
					m *= 1.79284291400159 - 0.85373472095314 *(a0*a0 + h*h);

					// Compute final noise value at P
					float3 g;
					g.x = a0.x  * x0.x + h.x  * x0.y;
					g.yz = a0.yz * float2(x1.x, x2.x) + h.yz * float2(x1.y, x2.y);
					return 130.0 * dot(m, g);
				}


			// #define UNITY_MATRIX_M _Object2World  // For Unity 4.X

			// Uniform variables.


			uniform float4x4 MATRIX_VP_INV;
			uniform sampler2D _TexRefraction;
			uniform float _RefrScale;

			uniform float _UnitPerUV;
			

			uniform float3 _DirDirectionalLight;
			uniform half3 _ColDirectionalLight;
			uniform float _Shininess;

			uniform half3 _ColSurface;
			uniform half3 _ColShore;
			uniform half3 _ColDeep;
			uniform float _Smoothness;
			uniform float _ThresDeepest;
			uniform float _Extinction;

			uniform float2 _VecWind;
			uniform sampler2D _TexNormal;
			uniform half _WaveIntensity;


			uniform float _R0;
			uniform samplerCUBE _ReflectionEnv;

			uniform sampler2D _TexFoam;
			uniform float _FoamDepthMin;
			uniform float _FoamDepthMax;
			




			struct App2Vert
			{
				float3 posObj : POSITION;
				half4 color :COLOR;
				float2 uv : TEXCOORD0;
			};

			struct Vert2Frag
			{
				float4 posClip : SV_POSITION;
				float3 posWorld : TEXCOORD0;
				float3 posObj : TEXCOORD1;
				float2 uv : TEXCOORD2;
				float4 xyInRange0w : TEXCOORD4;
				float depth : TEXCOORD5;
			};	


			float3 ClipToWorld(float4 posClip){
				float4 pos = mul(MATRIX_VP_INV, posClip);
				return pos.xyz / pos.w;
			}

			// Input uv and calculate normal in world space
			/* Deprecated, because UVs are needed in pixel shader.
			half3 ComputeNormal(float2 uv, half4 wavesIntensity, float2 uvWindOffset)
			{
		
				float2 uvNormal[4] = { uv*1.6  + uvWindOffset* 0.4 ,
					uv*0.8  + uvWindOffset * 0.2	 ,
					uv*0.5  + uvWindOffset * 0.1  ,
					uv*0.3  + uvWindOffset * 0.05   };


				half3 normal = half3(0, 0, 1);

				for (int i = 0; i < 3; ++i)
				{
					normal += UnpackNormal(tex2D(_TexNormal, uvNormal[i])) *wavesIntensity[i];
				}
				normal.xyz = normal.xzy;  // Tangent space to world space.

				return normalize(normal);
			}
			*/

			half3 FresnelR(float3 normal, float3 dirView, float R0){
				// Schlick's Fresnel approximation
				float NdotV = dot(normal, dirView);
				if(NdotV < 0 ) NdotV = -NdotV; // This is a hack, in case when looking from back of the surface by mistake
            	float oneMinusNdotV5 = pow(1.0 - NdotV, 5.0);
				return lerp(oneMinusNdotV5, 1, R0);
			}
			

			half3 Specular(float3 dirToCamera, float3 normal, float fresnelR){
				// https://www.gamedev.net/articles/programming/graphics/rendering-water-as-a-post-process-effect-r2642/
				half dotSpec = dot(reflect(-dirToCamera, normal), -_DirDirectionalLight) * 0.5 + 0.5;  // Half-Lambertian like
				//return half3(dotSpec, dotSpec, dotSpec);
				half3 colSpec = (1.0 - fresnelR) * saturate(-_DirDirectionalLight.y) * ((pow(dotSpec, 512.0)) * (_Shininess * 1.8 + 0.2));
				colSpec += colSpec * 25 * saturate(_Shininess - 0.05);	
				return colSpec;

			}


			half3 ColRefraction(half3 colUnderwater, float depth, float offshore, float cosTheta){
			
				half3 colLit = _ColDirectionalLight.rgb;
				half3 colSurf = lerp(_ColShore, _ColSurface, offshore);
				half3 colRefr = lerp(colUnderwater, colLit*normalize(colSurf), saturate(depth * _Extinction / (cosTheta * _Smoothness + 0.2	)));
				colRefr = lerp(colRefr, _ColDeep * normalize(colSurf), depth*0.2);

				// TODO:Refinement
				return colRefr;
			}

			half4 Foam(float depth, half4 wavesIntensity){
				return saturate((_FoamDepthMin - depth) / (_FoamDepthMax - _FoamDepthMin)) * wavesIntensity / (2.0 * _WaveIntensity) ;
			}
	

			
			Vert2Frag vert (App2Vert a2v)
			{
				Vert2Frag v2f;
				
				float4x4 mat = transpose(UNITY_MATRIX_MVP);
	
				v2f.posClip = UnityObjectToClipPos(float4(a2v.posObj, 1.0));
				v2f.posWorld = mul(unity_ObjectToWorld, float4(a2v.posObj, 1.0));
				v2f.posObj = a2v.posObj;
				v2f.uv = a2v.uv; 
				// Do not divide by w here, otherwise interpolated NDC will be distorted.
				v2f.xyInRange0w = ComputeGrabScreenPos(v2f.posClip);  
				v2f.depth = a2v.color.b	 	;


				return v2f;
			}
			
			half4 frag (Vert2Frag v2f) : SV_Target
			{

				float depth = v2f.depth;
				float2 uv = v2f.posWorld.xz / _UnitPerUV;
				float2 uvWindOffset =  _Time.x * _VecWind;  // _Time.x is t/20, where t is in second

				float2 noise;  
				// _Time.y is t in second
				noise.x = snoise(uv * 4  + uvWindOffset *2 );  // Large and slow noise
				noise.y = snoise(uv * 8 + uvWindOffset * 10);  // Detailed and fast noise

				// Simplex noise is in [-1, 1], remapping to [0,1].
				float2 noise01 = noise*0.5+0.5;

				// Noise-modulated intensity of 4 waves.
				float4 wavesIntensity = float4(saturate(noise01.x - noise01.y), noise01.x, noise01.y, noise01.x * noise01.y)* _WaveIntensity;
				wavesIntensity = clamp(wavesIntensity, 0.01, _WaveIntensity*2.0) ;


//////////////////////////////////////////////////////////////

				float2 uvWaves[4] = { uv*1.6  + uvWindOffset*0.4 ,
					uv*0.8  + uvWindOffset * 0.2 ,
					uv*0.5  + uvWindOffset * 0.3,
					uv*0.3  + uvWindOffset * 0.05	 }; //0.05


				float3 normal = half3(0, 0, 1);

				for (int i = 0; i < 4; ++i)
				{
					normal += UnpackNormal(tex2D(_TexNormal, uvWaves[i] ))*wavesIntensity[i];
				}




				normal.xyz = normal.xzy;  // Tangent space to world space.
				//normal = normal* 0.5+0.5;
				normal =  normalize(normal);
				//return half4(normal, 1.0);

/////////////////////////////////////////////////////////////




				float offshore = saturate(log(1.0-depth) / log(1.0-_ThresDeepest));
				half3 colSurf = lerp(_ColShore, _ColSurface, offshore);

				float2 uvNdc = v2f.xyInRange0w.xy / v2f.xyInRange0w.w;
				// Refraction: Perturb UVs in consideration of depth.
				float scale = _RefrScale * depth;
				float2 delta = -scale * normal.xz;  // Fake refraction: distort uv underwater with normal

				
				
				uvNdc += delta;

				// Reflected color component: TODO
				float3 dirToCameraWorld = normalize(WorldSpaceViewDir(float4(v2f.posObj, 1.0)));
				_DirDirectionalLight = normalize(_DirDirectionalLight);

				

				half3 colUnderwater = tex2D(_TexRefraction, uvNdc);
				half3 colRefr = ColRefraction(colUnderwater, depth, offshore, dot(float3(0,1,0), dirToCameraWorld));


			

				float3 dirReflWorld = reflect(-dirToCameraWorld, normal);





				float fresnelR = FresnelR(normal, dirToCameraWorld, _R0);  // Default 0.02 is calculated according to refraction index of water.

				
				if(dirReflWorld.y<0) {
					// Bounce again.
					dirReflWorld = reflect(dirReflWorld, float3(0,1,0));
					fresnelR *= FresnelR(float3(0,1,0), -dirReflWorld, _R0);
				}
				
				half3 colRefl = saturate(texCUBE(_ReflectionEnv, dirReflWorld).rgb);
//				colRefl = lerp(colRefr, colRefl, saturate(dot(dirReflWorld, float3(0, 1, 0))));
				half3 colSpec = Specular(dirToCameraWorld, normal, fresnelR);

				half4 foamsIntensity = Foam(depth, wavesIntensity);
				





           		half3 col = (1-fresnelR)*colRefr + fresnelR*colRefl + colSpec;


				for (int i = 0; i < 4; ++i)
				{
					col += tex2D(_TexFoam, uvWaves[i] + delta) *foamsIntensity[i];
				}
		
				//return float4(v2f.uv, 0, 1);
				//return wavesIntensity;
				//return float4(frac(uvWaves[2]), 0,1);
				return float4(col, 1.0f);
			}
			ENDCG
		}
	}
}