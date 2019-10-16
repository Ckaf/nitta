import * as React from "react";
import { haskellApiService } from "../../../services/HaskellApiService";
import { ProcessTimelines, ViewPointID, TimelinePoint, TimelineWithViewPoint } from "../../../gen/types";

interface Props {
    nId: string;
}

interface State {
    nId: string | null;
    data: ProcessTimelines<number> | null;
    pIdIndex: Record<number, TimelinePoint<number>> | null;
    detail: TimelinePoint<number>[];
    highlight: Highlight;
}

interface Highlight {
    up: number[];
    current: number[];
    down: number[];
}

export class ProcessView extends React.Component<Props, State> {
    // TODO: diff from previous synthesis process step
    // TODO: highlight point by click on info part
    constructor(props: Props) {
        super(props);
        this.state = {
            nId: null,
            data: null,
            pIdIndex: null,
            detail: [],
            highlight: {
                up: [],
                current: [],
                down: [],
            },
        };
        this.requestTimelines = this.requestTimelines.bind(this);
        this.renderPoint = this.renderPoint.bind(this);
        this.selectPoint = this.selectPoint.bind(this);
    }

    static getDerivedStateFromProps(props: Props, state: State) {
        console.log("> ProcessView.getDerivedStateFromProps", props.nId);
        if (props.nId && props.nId !== state.nId) {
            console.log("> ProcessView.getDerivedStateFromProps - new state");
            return { nId: props.nId, data: null } as State;
        }
        return null;
    }

    componentDidMount() {
        console.log("> ProcessView.componentDidMount", this.state.nId);
        this.requestTimelines(this.state.nId!);
    }

    componentDidUpdate(prevProps: Props, prevState: State, snapshot: any) {
        console.log("> ProcessView.componentDidUpdate");
        if (prevState.nId !== this.state.nId) {
            this.requestTimelines(this.state.nId!);
        }
    }

    requestTimelines(nId: string) {
        console.log("> ProcessView.requestTimelines");
        haskellApiService.getTimelines(nId)
            .then((response: { data: ProcessTimelines<number> }) => {
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
                    data: this.resortTimeline(response.data),
                    pIdIndex: pIdIndex,
                });
            })
            .catch((err: any) => console.log(err));
    }

    resortTimeline(data: ProcessTimelines<number>) {
        let result: ProcessTimelines<number> = {
            timelines: [],
            verticalRelations: data.verticalRelations,
        };
        function cmp(a: TimelineWithViewPoint<number>, b: TimelineWithViewPoint<number>) {
            if (a.timelineViewpoint.component < b.timelineViewpoint.component) return -1;
            if (a.timelineViewpoint.component > b.timelineViewpoint.component) return 1;
            return 0;
        }
        let tmp: TimelineWithViewPoint<number>[] = data.timelines.sort(cmp);
        function extract(p: (id: ViewPointID) => boolean) {
            let newTmp: TimelineWithViewPoint<number>[] = [];
            tmp.forEach(e => {
                if (p(e.timelineViewpoint)) {
                    result.timelines.push(e);
                } else {
                    newTmp.push(e);
                }
            });
            tmp = newTmp;
        }
        extract(e => e.component.length === 0);
        extract(e => e.level === "CAD");
        extract(e => e.level === "Fun");
        extract(e => e.level === "EndPoint");
        extract(e => true);
        return result;
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
            if (this.state.highlight.up.indexOf(id) >= 0) {
                return <span key={i} className="upRelation" onClick={() => this.selectPoint(point)}>{s}</span>;
            }
            if (this.state.highlight.current.indexOf(id) >= 0) {
                return <span key={i} className="current" onClick={() => this.selectPoint(point)}>{s}</span>;
            }
            if (this.state.highlight.down.indexOf(id) >= 0) {
                return <span key={i} className="downRelation" onClick={() => this.selectPoint(point)}>{s}</span>;
            }
        }
        return <span key={i} onClick={() => this.selectPoint(point)}>{s}</span>;
    }

    selectPoint(point: TimelinePoint<number>[]) {
        let highlight: Highlight = { up: [], current: [], down: [] };
        point.forEach(p => {
            let id: number = p.pID;
            highlight.current.push(p.pID);
            this.state.data!.verticalRelations.forEach(e => {
                let up = e[0], down = e[1];
                if (highlight.up.indexOf(up) === -1) {
                    if (id === down) { highlight.up.push(up); }
                }
                if (highlight.down.indexOf(down) === -1) {
                    if (id === up) { highlight.down.push(down); }
                }
            });
        });
        this.setState({
            detail: point,
            highlight: highlight,
        });
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
            <div className="columns large-7">
                <pre className="squeeze"><u>{viewColumnHead}{" ".repeat(viewColumnLength - viewColumnHead.length)} | timeline</u></pre>
                {this.state.data.timelines.map(
                    (e, i) => {
                        return this.renderLine(i, viewColumnLength, e.timelineViewpoint, e.timelinePoints);
                    })}
            </div>
            <div className="columns large-5">
                <pre className="squeeze">------------------------------</pre>
                <pre className="squeeze upRelation">upper related:</pre>
                {this.state.highlight.up.map(e => <pre className="squeeze">- {this.state.pIdIndex![e].pInfo}</pre>)}
                <pre className="squeeze">------------------------------</pre>
                <pre className="squeeze current">current:</pre>
                {this.state.detail.map(e => <pre className="squeeze">- {e.pInfo}</pre>)}
                <pre className="squeeze">------------------------------</pre>
                <pre className="squeeze downRelation">bottom related:</pre>
                {this.state.highlight.down.map(e => <pre className="squeeze">- {this.state.pIdIndex![e].pInfo}</pre>)}
            </div>
        </div>;
    }
}
