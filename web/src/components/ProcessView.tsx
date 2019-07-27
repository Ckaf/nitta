import * as React from "react";
import { haskellAPI } from "../middleware/haskell-api";
import { ProcessTimelines, ViewPointID, TimelinePoint } from "../gen/types";

interface ProcessViewProps {
    nId: string;
}

interface ProcessViewState {
    nId: string;
    data: ProcessTimelines<number>;
    pIdIndex: Record<number, TimelinePoint<number>>;
    detail: TimelinePoint<number>[];
    up: number[];
    current: number[];
    down: number[];
}

export class ProcessView extends React.Component<ProcessViewProps, ProcessViewState> {
    state: ProcessViewState = { nId: null, data: null, pIdIndex: null, detail: [], up: [], current: [], down: [] };

    constructor(props) {
        super(props);
        this.renderPoint = this.renderPoint.bind(this);
        this.selectPoint = this.selectPoint.bind(this);
    }

    static getDerivedStateFromProps(props: ProcessViewProps, state: ProcessViewState) {
        console.log("> ProcessView.getDerivedStateFromProps", props.nId);
        if (props.nId && props.nId !== state.nId) {
            console.log("> ProcessView.getDerivedStateFromProps - new state");
            return { nId: props.nId, data: null } as ProcessViewState;
        }
        return null;
    }

    componentDidMount() {
        console.log("> ProcessView.componentDidMount", this.state.nId);
        this.requestTimelines(this.state.nId);
    }

    componentDidUpdate(prevProps: ProcessViewProps, prevState: ProcessViewState, snapshot: any) {
        console.log("> ProcessView.componentDidUpdate");
        if (prevState.nId !== this.state.nId) {
            this.requestTimelines(this.state.nId);
        }
    }

    requestTimelines(nId: string) {
        console.log("> ProcessView.requestTimelines");
        haskellAPI.getTimelines(nId)
            .then((response: {data: ProcessTimelines<number>}) => {
                console.log("> ProcessView.requestTimelines - done");
                let pIdIndex: Record<number, TimelinePoint<number>> = {};
                response.data.timelines.forEach(vt => {
                    vt.timelinePoints.forEach(point => {
                        point.forEach(e => {
                            const x: number = e.pID;
                            pIdIndex[x] = e;
                        });
                    });
                });
                this.setState({
                    data: response.data,
                    pIdIndex: pIdIndex,
                });
            })
            .catch((err: any) => console.log(err));
    }

    viewpoint2string(view: ViewPointID): string {
        return view.component + "@" + view.level;
    }

    renderLine(i: number, viewLength: number, view: ViewPointID, points: TimelinePoint<number>[][]) {
        let v = this.viewpoint2string(view);
        let n = viewLength - v.length;
        return <pre key={i} className="squeeze">{" ".repeat(n)}{v} | {points.map(this.renderPoint)}</pre>;
    }

    renderPoint(point: TimelinePoint<number>[], i: number) {
        let s: string = ".";
        if (point.length === 1) {
            s = "*";
        }
        if (point.length > 1) {
            s = "#";
        }
        for (let j = 0; j < point.length; j++) {
            const id = point[j].pID;
            if (this.state.up.indexOf(id) >= 0) {
                return <span key={i} className="upRelation" onClick={() => this.selectPoint(point)}>{s}</span>;
            }
            if (this.state.current.indexOf(id) >= 0) {
                return <span key={i} className="current" onClick={() => this.selectPoint(point)}>{s}</span>;
            }
            if (this.state.down.indexOf(id) >= 0) {
                return <span key={i} className="downRelation" onClick={() => this.selectPoint(point)}>{s}</span>;
            }
        }
        return <span key={i} onClick={() => this.selectPoint(point)}>{s}</span>;
    }

    selectPoint(point: TimelinePoint<number>[]) {
        let up: number[] = [];
        let current: number[] = [];
        let down: number[] = [];
        point.forEach(p => {
            let id: number = p.pID;
            current.push(id);
            this.state.data.verticalRelations.forEach(e => {
                if (up.indexOf(id) === -1) {
                    if (e[1] === id) { up.push(e[0]); }
                }
                if (down.indexOf(id) === -1) {
                    if (e[0] === id) { down.push(e[1]); }
                }
            });
        });
        this.setState({ detail: point, up: up, current: current, down: down });
    }

    render() {
        if (!this.state.data) {
            return <pre>LOADING</pre>;
        }
        if (this.state.data.timelines.length === 0) {
            return <pre>EMPTY PROCESS TIMELINE</pre>;
        }
        let viewColumnHead = "view point";
        let viewColumnLength: number = viewColumnHead.length;
        this.state.data.timelines.forEach(e => {
            let l: number = this.viewpoint2string(e.timelineViewpoint).length;
            if (l > viewColumnLength) {
                viewColumnLength = l;
            }
        });
        return <div className="row">
            <div className="columns large-8">
                <pre className="squeeze"><u>{viewColumnHead}{" ".repeat(viewColumnLength - viewColumnHead.length)} | timeline</u></pre>
                {this.state.data.timelines.map(
                    (e, i) => {
                        return this.renderLine(i, viewColumnLength, e.timelineViewpoint, e.timelinePoints);
                    })}
            </div>
            <div className="columns large-4">
                <pre className="squeeze">------------------------------</pre>
                <pre className="squeeze">upper related:</pre>
                {this.state.up.map(e => <pre className="squeeze">{JSON.stringify(this.state.pIdIndex[e].pInfo, null, 2)}</pre>) }
                <pre className="squeeze">------------------------------</pre>
                <pre className="squeeze">current:</pre>
                {this.state.detail.map(e => <pre className="squeeze">{JSON.stringify(e.pInfo)}</pre>)}
                <pre className="squeeze">------------------------------</pre>
                <pre className="squeeze">bottom related:</pre>
                {this.state.down.map(e => <pre className="squeeze">{JSON.stringify(this.state.pIdIndex[e].pInfo, null, 2)}</pre>) }
            </div>
        </div>;
    }
}
