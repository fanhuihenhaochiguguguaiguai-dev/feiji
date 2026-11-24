import type { Camera } from '@babylonjs/core/Cameras/camera';
import { Constants } from '@babylonjs/core/Engines/constants';
import { FrameGraph } from '@babylonjs/core/FrameGraph/frameGraph';
import { FrameGraphObjectList } from '@babylonjs/core/FrameGraph/frameGraphObjectList';
import { backbufferColorTextureHandle } from '@babylonjs/core/FrameGraph/frameGraphTypes';
import { FrameGraphFXAATask } from '@babylonjs/core/FrameGraph/Tasks/PostProcesses/fxaaTask';
import { FrameGraphImageProcessingTask } from '@babylonjs/core/FrameGraph/Tasks/PostProcesses/imageProcessingTask';
import { FrameGraphObjectRendererTask } from '@babylonjs/core/FrameGraph/Tasks/Rendering/objectRendererTask';
import { FrameGraphCascadedShadowGeneratorTask } from '@babylonjs/core/FrameGraph/Tasks/Rendering/csmShadowGeneratorTask';
import { FrameGraphShadowGeneratorTask } from '@babylonjs/core/FrameGraph/Tasks/Rendering/shadowGeneratorTask';
import { FrameGraphClearTextureTask } from '@babylonjs/core/FrameGraph/Tasks/Texture/clearTextureTask';
import type { DirectionalLight } from '@babylonjs/core/Lights/directionalLight';
import { CascadedShadowGenerator } from '@babylonjs/core/Lights/Shadows/cascadedShadowGenerator';
import { ShadowGenerator } from '@babylonjs/core/Lights/Shadows/shadowGenerator';
import type { AbstractMesh } from '@babylonjs/core/Meshes/abstractMesh';
import { ThinImageProcessingPostProcess } from '@babylonjs/core/PostProcesses/thinImageProcessingPostProcess';
import type { Scene } from '@babylonjs/core/scene';

/** Owns the linear scene attachments and the only display transform. */
export class FlightRenderGraph {
  readonly graph:FrameGraph;
  private readonly casters:AbstractMesh[]=[];
  private readonly shadow:FrameGraphShadowGeneratorTask;
  private width=0;
  private height=0;
  private building:Promise<void>|null=null;
  constructor(private readonly scene:Scene,camera:Camera,sun:DirectionalLight){
    const graph=this.graph=new FrameGraph(scene),device=scene.getEngine(),caps=device.getCaps();
    const size={width:100,height:100},sizeIsPercentage=true;
    const color=graph.textureManager.createRenderTargetTexture('线性 HDR',{
      size,sizeIsPercentage,options:{types:[caps.textureHalfFloatRender?Constants.TEXTURETYPE_HALF_FLOAT:Constants.TEXTURETYPE_FLOAT],
        formats:[Constants.TEXTUREFORMAT_RGBA]},
    });
    const depth=graph.textureManager.createRenderTargetTexture('场景深度',{
      size,sizeIsPercentage,options:{formats:[Constants.TEXTUREFORMAT_DEPTH24]},
    });
    const display=graph.textureManager.createRenderTargetTexture('显示空间',{
      size,sizeIsPercentage,options:{formats:[Constants.TEXTUREFORMAT_RGBA],types:[Constants.TEXTURETYPE_UNSIGNED_BYTE]},
    });
    const clear=new FrameGraphClearTextureTask('初始化颜色与深度',graph);
    clear.targetTexture=color;clear.depthTexture=depth;clear.color.copyFrom(scene.clearColor);
    clear.convertColorToLinearSpace=true;clear.clearColor=true;clear.clearDepth=true;
    graph.addTask(clear);
    const csm=CascadedShadowGenerator.IsSupported?new FrameGraphCascadedShadowGeneratorTask('太阳阴影',graph):null;
    if(csm){csm.numCascades=2;csm.shadowMaxZ=110;csm.lambda=.61;csm.stabilizeCascades=true;}
    const shadow=this.shadow=csm??new FrameGraphShadowGeneratorTask('太阳阴影',graph);
    shadow.camera=camera;shadow.light=sun;shadow.mapSize=1024;shadow.normalBias=.045;shadow.bias=.0007;
    shadow.objectList=new FrameGraphObjectList();shadow.objectList.meshes=this.casters;
    graph.addTask(shadow);
    const world=new FrameGraphObjectRendererTask('机库或空域',graph,scene);
    world.isMainObjectRenderer=true;world.camera=camera;world.targetTexture=clear.outputTexture;
    world.depthTexture=clear.outputDepthTexture;world.objectList=new FrameGraphObjectList();world.shadowGenerators=[shadow];
    graph.addTask(world);
    const transform=new ThinImageProcessingPostProcess('ACES 显示变换',device,{scene});
    transform.imageProcessingConfiguration=scene.imageProcessingConfiguration;
    const grade=new FrameGraphImageProcessingTask('ACES 显示变换',graph,transform);
    grade.sourceTexture=world.outputTexture;grade.targetTexture=display;graph.addTask(grade);
    const aa=new FrameGraphFXAATask('边缘抗锯齿',graph);
    aa.sourceTexture=grade.outputTexture;aa.targetTexture=backbufferColorTextureHandle;graph.addTask(aa);
  }
  cast(mesh:AbstractMesh){if(!this.casters.includes(mesh))this.casters.push(mesh);}
  drop(mesh:AbstractMesh){const index=this.casters.indexOf(mesh);if(index>=0)this.casters.splice(index,1);}
  quality(enabled:boolean,enhanced:boolean){
    this.shadow.disabled=!enabled;
    this.shadow.filteringQuality=enhanced?ShadowGenerator.QUALITY_HIGH:ShadowGenerator.QUALITY_MEDIUM;
  }
  prepare(){
    const device=this.scene.getEngine(),width=device.getRenderWidth(),height=device.getRenderHeight();
    if(this.building)return this.building;
    if(this.width===width&&this.height===height)return null;
    this.width=width;this.height=height;
    this.building=this.graph.buildAsync(false).then(()=>{this.scene.frameGraph=this.graph;}).finally(()=>{this.building=null;});
    return this.building;
  }
}
