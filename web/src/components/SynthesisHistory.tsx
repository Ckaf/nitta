import { AxiosError, AxiosResponse } from "axios";
import React, { FC, ReactElement, useContext, useEffect, useState } from "react";
import ReactTable, { Column } from "react-table";

import { AppContext, IAppContext } from "app/AppContext";
import { Node, Sid, api } from "services/HaskellApiService";
import { showDecision } from "./SubforestTables/Columns";

type Row = { original: Node; index: number };

export interface ISynthesisHistoryProps {
  reverse: boolean;
}

export const SynthesisHistory: FC<ISynthesisHistoryProps> = (props) => {
  const appContext = useContext(AppContext) as IAppContext;
  const [synthesisHistory, setHistory] = useState<Node[]>();
  const style = {
    fontWeight: 600,
    width: "100%",
  };

  useEffect(() => {
    api
      .getRootPath(appContext.selectedSid)
      .then((response: AxiosResponse<Node[]>) => {
        let result = response.data;
        if (props.reverse) {
          result = result.reverse();
        }
        setHistory(result);
      })
      .catch((err: AxiosError) => console.log(err));
  }, [appContext.selectedSid, props.reverse]);

  function Table(props: { name: string; columns: Column[]; history: Node[] }) {
    if (props.history.length === 0)
      return (
        <small>
          <pre style={style}>{props.name}: NOTHING</pre>
        </small>
      );
    return (
      <small style={style}>
        <pre className="squeze h5">{props.name}</pre>
        <ReactTable
          defaultPageSize={props.history.length}
          minRows={props.history.length}
          showPagination={false}
          columns={props.columns}
          data={props.history}
        />
        <br />
      </small>
    );
  }

  function stepNumber(row: Row) {
    return props.reverse ? synthesisHistory!.length - row.index : row.index + 1;
  }

  function stepColumn(onUpdateNid: (sid: Sid) => void) {
    return {
      Header: "step",
      maxWidth: 40,
      Cell: (row: Row) => {
        let sid = row.original.sid;
        if (sid === appContext.selectedSid) return <>{stepNumber(row)}</>;
        return (
          <button className="btn-link bg-transparent p-0 border-0" onClick={() => onUpdateNid(sid)}>
            {stepNumber(row)}
          </button>
        );
      },
    };
  }

  function textColumn(columnName: string, f: (n: Node) => string | ReactElement, maxWidth?: number, minWidth?: number) {
    return {
      Header: columnName,
      style: style,
      maxWidth: maxWidth,
      minWidth: minWidth,
      Cell: (row: { original: Node }) => f(row.original),
    };
  }

  if (synthesisHistory == null) return <pre>LOADING...</pre>;

  return (
    <>
      <Table
        name="History"
        history={synthesisHistory}
        columns={[
          stepColumn(appContext.setSid),
          textColumn("decision type", (n: Node) => n.decision.tag, 160),
          textColumn("description", (n: Node) => {
            if (n.sid === "-") return <>INITIAL STATE</>;
            return showDecision(n.decision);
          }),
        ]}
      />
    </>
  );
};
