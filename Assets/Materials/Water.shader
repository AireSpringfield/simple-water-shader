// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'
// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Custom/Water2"
{
	Properties
	{
		[Header(Features)]
		[Toggle(USE_DIRECTIONAL_LIGHT)] _UseDirectionalLight("Directional Light", Float) = 0
		[Toggle(USE_MEAN_SKY_RADIANCE)] _UseMeanSky("Mean sky radiance", Float) = 0
		[Toggle(USE_FILTERING)] _UseFiltering("Filtering", Float) = 0
		[Toggle(USE_FOAM)] _UseFoam("Foam", Float) = 0
		[Toggle(BLINN_PHONG)] _UsePhong("Blinn Phong", Float) = 0



		[Header(Basic Settings)]
		_ColSurface("Water Surface Color", Color) = (0.0078, 0.5176, 0.7)
		_ColShore("Shore Color Tint", Color) = (0.0, 0.9, 1.0)
		_ThresDeepest("Deepest If Depth Exceeds This", Range(0.01, 0.99)) = 0.40
		_RangeShore("Shore Distance When Deepest Reached", Float) = 2.0
		_ColDeep("Deep Water Color Tint", Color) = (0.0039, 0.00196, 0.145)
		_Extinction("Color Extinction Rate Under Water", Range(1.0, 2.0)) = 1.0

		[Header(Wind And Waves)]
		_VecWind("Velocity of Wind (XY)", Vector) = (1, 1, 0, 0)
		_NormalMap("Normal Map", 2D) = ""{}


		[Header(Directional Light)]
		_DirDirectionalLight("Light Direction", Vector) = (1, -1, 1)
		_ColDirectionalLight("Light Color", Color) = (1, 1, 1)
		_Shininess("Shininess", Range(0, 3)) = 0.12

		[Header(Refraction)]
		_RefrScale("Underwater Refraction Level", Range(0, 0.05)) = 0.02

		[Header(Reflection)]
		_R0("Reflection Rate When Seeing Above Water", Range(0, 0.2)) = 0.02
		_ReflectionEnv("Reflection Environment Cubemap", Cube) = ""{}


	}
	SubShader
	{
		Tags { "RenderType"="Transparent" }

		GrabPass{ "_TexForRefraction" }





		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			// make fog work
			// #pragma multi_compile_fog
			
			#include "UnityCG.cginc"
			#include "snoise.cginc"

			// #define UNITY_MATRIX_M _Object2World  // For Unity 4.X
			//#define UNITY

			uniform float4x4 MATRIX_VP_INV;
			uniform sampler2D _TexForRefraction;
			uniform float _RefrScale;
			uniform sampler2D _CameraDepthTexture;
			

			uniform float3 _DirDirectionalLight;
			uniform half3 _ColDirectionalLight;
			uniform float _Shininess;

			uniform half3 _ColSurface;
			uniform half3 _ColShore;
			uniform half3 _ColDeep;
			uniform float _ThresDeepest;
			uniform float _Extinction;

			uniform float2 _VecWind;
			uniform sampler2D _NormalMap;


			uniform float _R0;
			uniform samplerCUBE _ReflectionEnv;
			




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

			float3 PerturbNormal(in float3 normal, Vert2Frag v2f){
				float2 windOffset = _VecWind * _Time;
				float2 noise;
				noise.x = 0;//snoise(v2f.posWorld.xz * 0.01  + windOffset * 0.005); // large and slower noise 
				noise.y = 0;//;snoise(v2f.posWorld.xz * 0.1 + windOffset * 0.02); // smaller and faster noise

				float4 uv = float4(v2f.uv + windOffset * 0.01 + noise.x, v2f.uv + windOffset * 0.01 + noise.y);
				
				return normalize(UnpackNormal(tex2D(_NormalMap, uv.xy))).xzy; 
				normal += UnpackNormal(tex2D(_NormalMap, uv.xy));
				normal += UnpackNormal(tex2D(_NormalMap, uv.zw));

				return float3(0,1,0);
			}

			half3 FresnelR(float3 normal, float3 dirView, float R0){
				// Schlick's Fresnel approximation
				float NdotV5 = pow(1.0 - dot(normal, dirView), 5.0);
				return lerp(NdotV5, 1, R0);
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
				//half3 colTint = lerp(_ColSurface, _ColDeep, depth);
				//colTint = lerp(_ColShore, colTint, offshore);
				//half3 colUnder = lerp(colUnderwater, _ColDeep, depth);
				// return lerp(colUnderwater, colTint, exp((depth - 1) * _Extinction));

				
				half3 colLit = _ColDirectionalLight.rgb;

				half3 colSurf = lerp(_ColShore, _ColSurface, offshore);
				half3 colRefr = lerp(colUnderwater, colLit*normalize(colSurf), saturate(depth * 0.5 / cosTheta));
				colRefr = lerp(colRefr, _ColDeep * normalize(colSurf), depth*0.2);

				// TODO:Refinement
				return colRefr;
			}
	

			
			Vert2Frag vert (App2Vert a2v)
			{
				Vert2Frag v2f;
				
				float4x4 mat = transpose(UNITY_MATRIX_MVP);
	
				v2f.posClip = UnityObjectToClipPos(float4(a2v.posObj, 1.0));
				v2f.posWorld = mul(unity_ObjectToWorld, float4(a2v.posObj, 1.0));
				v2f.posObj = a2v.posObj;
				v2f.uv = a2v.uv; 
				v2f.xyInRange0w = ComputeGrabScreenPos(v2f.posClip);
				v2f.depth = a2v.color.a;
				return v2f;
			}
			
			half4 frag (Vert2Frag v2f) : SV_Target
			{

				//return half4(v2f.depth,v2f.depth,v2f.depth,1);
				float depth = v2f.depth;

				float3 normal = UnpackNormal(tex2D(_NormalMap, v2f.uv)).xzy;

				normal = PerturbNormal(normal, v2f);
				//normal = float3(0,1,0);
				


				// Reflected color component: TODO
				float3 dirToCameraWorld = normalize(WorldSpaceViewDir(float4(v2f.posObj, 1.0)));
				float3 dirToCameraObj = normalize(ObjSpaceViewDir(float4(v2f.posObj, 1.0)).xyz);
				_DirDirectionalLight = normalize(_DirDirectionalLight);



				float offshore = saturate(log(1.0-depth) / log(1.0-_ThresDeepest));
				half3 colSurf = lerp(_ColShore, _ColSurface, offshore);

				float2 uvNdc = v2f.xyInRange0w.xy / v2f.xyInRange0w.w;
				// Refraction: Perturb UVs in consideration of depth.
				float scale = _RefrScale * depth;
				float2 delta = scale * float2(sin(_Time.y + 3.0 * depth), sin(_Time.y + 5.0 * depth));

				uvNdc += delta;
				

				half3 colUnderwater = tex2D(_TexForRefraction, uvNdc);
				half3 colRefr = ColRefraction(colUnderwater, depth, offshore, dot(float3(0,1,0), dirToCameraWorld));


				

				float3 dirReflObj = reflect(-dirToCameraObj, normal);
				float3 dirReflWorld = mul(unity_ObjectToWorld, float4(dirReflObj, 0.0)).xyz;

				float fresnelR = FresnelR(normal, dirToCameraObj, _R0);  // 0.02 is calculated according to refraction index of water.

				half3 colRefl = texCUBE(_ReflectionEnv, dirReflWorld).rgb;
				//half3 colRefr = tex2D(_TexForRefraction, v2f.xyInRange0w.xy/ v2f.xyInRange0w.w);
				half3 colSpec = Specular(dirToCameraObj, normal, fresnelR);
				//return half4(colRefl + colSpec, 1);


           		half3 col = (1-fresnelR)*colRefr + fresnelR*colRefl + colSpec;

		
				return float4(col, 1.0f);
				
				






/*
				// sample the texture
				half4 col = tex2D(_MainTex, v2f.uv);
				// apply fog
				col.rgb = tex2D(_ReflectionTexture, v2f.uv).rgb;
				return col;*/
			}
			ENDCG
		}
	}
}