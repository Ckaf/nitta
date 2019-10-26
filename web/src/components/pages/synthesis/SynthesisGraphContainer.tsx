import * as React from "react";
import { Button } from "react-bootstrap";
import { SynthesisGraphView } from "./SynthesisGraphView";
import { AppContext, IAppContext } from "../../app/AppContext";

export const SynthesisGraphContainer: React.FC = () => {
  const appContext = React.useContext(AppContext) as IAppContext;

  const step = 100;
  const minSynthesisGraphHeight = 200;
  const [synthesisGraphHeight, setSynthesisGraphHeight] = React.useState<number>(minSynthesisGraphHeight);

  const buttonAttrs = {
    className: "btn btn-sm mr-3"
  };

  const expandSynthesisGraphView = () => setSynthesisGraphHeight(synthesisGraphHeight + step);

  const reduceSynthesisGraphView = () => setSynthesisGraphHeight(synthesisGraphHeight - step);

  return (
    <div className="flex-grow-1">
      <div className="d-flex justify-content-between m-2">
        <div className="mr-3">
          <Button {...buttonAttrs} variant="link" onClick={() => expandSynthesisGraphView()}>
            Expand
          </Button>
          <Button {...buttonAttrs} variant="link" onClick={() => reduceSynthesisGraphView()}>
            Reduce
          </Button>
          <Button {...buttonAttrs} variant="link" onClick={() => appContext.reloadSelectedNode()}>
            Refresh
          </Button>
        </div>
        <span className="text-muted">black - processed node; white - in progress node; green - succees synthesis</span>
      </div>
      <div className="justify-content-center bg-light border" style={{ height: synthesisGraphHeight }}>
        <SynthesisGraphView />
      </div>
    </div>
  );
};
