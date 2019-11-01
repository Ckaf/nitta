import * as React from "react";
import Tree from "react-d3-tree";
import { haskellApiService } from "../../../services/HaskellApiService";
import { AppContext, IAppContext, SelectedNodeId } from "../../app/AppContext";
import { SynthesisNodeView } from "../../../gen/types";
import { Graph, JsonObjId } from "../../../gen/types_mock";
import { AxiosResponse, AxiosError } from "axios";

export const SynthesisGraphView: React.FC = () => {
  const appContext = React.useContext(AppContext) as IAppContext;

  const [dataGraph, setDataGraph] = React.useState<Graph[]>([] as Graph[]);
  const [nIds, setNIds] = React.useState<JsonObjId>({});
  const [currentSelectedNodeId, setCurrentSelectedNodeId] = React.useState<SelectedNodeId>("");

  const markNode = React.useCallback(
    (nid: SelectedNodeId, nidArray?: JsonObjId, color?: string) => {
      if (color === undefined) color = "blue";
      if (nidArray === undefined) nidArray = nIds;
      if (nidArray === null) return;

      if (color === "blue") {
        nidArray[nid].nodeSvgShapeOriginal = nidArray[nid].nodeSvgShape;
      }
      nidArray[nid].nodeSvgShape = {
        shape: "circle",
        shapeProps: {
          r: 10,
          cx: 0,
          cy: 0,
          fill: color
        }
      };
    },
    [nIds]
  );

  const unmarkNode = React.useCallback(
    (nid: SelectedNodeId) => {
      if (nid === null) return;
      let tmp: string = nIds[nid].nodeSvgShapeOriginal;
      let nids = nIds;
      nids[nid].nodeSvgShape = tmp;
      setNIds(nids);
    },
    [nIds]
  );

  const reloadSynthesisGraph = React.useCallback(() => {
    let reLastNidStep = /-[^-]*$/; // nInSeparator
    let nid = appContext.selectedNodeId;

    haskellApiService
      .getSynthesis()
      .then((response: AxiosResponse<[SynthesisNodeView, Array<SynthesisNodeView>]>) => {
        let nidArray: JsonObjId = {};
        let buildGraph = (gNode: Graph, dNode: [SynthesisNodeView, Array<SynthesisNodeView>]) => {
          let strNid: string = Object.values(dNode[0].svNnid).map(String).join("");
          gNode.name = reLastNidStep.exec(strNid)![0];
          gNode.nid = dNode[0].svNnid;
          nidArray[strNid] = gNode;
          if (dNode[0].svIsEdgesProcessed) markNode(strNid, nidArray, "black");
          if (dNode[0].svIsComplete) markNode(strNid, nidArray, "lime");
          gNode.attributes = {
            dec: dNode[0].svOptionType,
            ch: dNode[0].svDuration + " / " + dNode[0].svCharacteristic
          };
          gNode.status = dNode[0].svIsComplete;
          dNode[0].svCntx.forEach((e: string, i: number) => {
            gNode.attributes![i] = e;
          });
          gNode.children = [];
          dNode[1].forEach((e: any) => {
            var tmp: Graph = {};
            if (gNode.children != null) {
              gNode.children.push(tmp);
              buildGraph(tmp, e);
            }
          });
          return gNode;
        };

        let graph = buildGraph({}, response.data);
        nidArray["."] = graph;
        if (nid !== null) markNode(nid, nidArray);
        setDataGraph([graph]);
        setNIds(nidArray);
      })
      .catch((err: AxiosError) => console.log(err));
  }, [appContext.selectedNodeId, markNode]);

  React.useEffect(() => {
    if (currentSelectedNodeId === appContext.selectedNodeId && currentSelectedNodeId.length !== 0) return;
    if (appContext.selectedNodeId === "-" || currentSelectedNodeId.length === 0) {
      setCurrentSelectedNodeId(appContext.selectedNodeId);
      reloadSynthesisGraph();
      return;
    }
    if (!(appContext.selectedNodeId in nIds)) {
      setCurrentSelectedNodeId(appContext.selectedNodeId);
      reloadSynthesisGraph();
      return;
    }

    unmarkNode(currentSelectedNodeId);
    markNode(appContext.selectedNodeId);
    setCurrentSelectedNodeId(appContext.selectedNodeId);
    setDataGraph([dataGraph[0]]);
    return;
  }, [
    appContext.selectedNodeId,
    appContext.selectNode,
    currentSelectedNodeId,
    reloadSynthesisGraph,
    dataGraph,
    markNode,
    nIds,
    unmarkNode
  ]);

  if (!dataGraph === null || dataGraph.length === 0) {
    return (
      <div className="h-100 d-flex align-items-center justify-content-center text-black-50">
        <h1>Empty graph</h1>
      </div>
    );
  } else {
    return (
      <div className="h-100">
        <Tree
          data={dataGraph}
          nodeSize={{ x: 160, y: 60 }}
          separation={{ siblings: 1, nonSiblings: 1 }}
          pathFunc="diagonal"
          translate={{ x: 20, y: 40 }}
          collapsible={false}
          zoom={0.7}
          transitionDuration={0}
          nodeSvgShape={{
            shape: "circle",
            shapeProps: {
              r: 10,
              cx: 0,
              cy: 0,
              fill: "white"
            }
          }}
          styles={{
            nodes: {
              node: {
                name: { fontSize: "12px" },
                attributes: { fontSize: "10px" }
              },
              leafNode: {
                name: { fontSize: "12px" },
                attributes: { fontSize: "10px" }
              }
            }
          }}
          onClick={(node: any) => {
            appContext.selectNode(node.nid);
          }}
        />
      </div>
    );
  }
};
