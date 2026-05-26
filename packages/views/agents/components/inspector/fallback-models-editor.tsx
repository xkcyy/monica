"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Loader2, Plus, X } from "lucide-react";
import { runtimeModelsOptions } from "@multica/core/runtimes";
import { Input } from "@multica/ui/components/ui/input";
import {
  PickerItem,
  PropertyPicker,
} from "../../../issues/components/pickers";
import { useT } from "../../../i18n";

const MAX_FALLBACK_MODELS = 4;

const CHIP_CLASS =
  "inline-flex items-center gap-1 rounded-md bg-muted px-1.5 py-0.5 font-mono text-[11px] text-muted-foreground transition-colors hover:bg-muted/80";

interface FallbackModelsEditorProps {
  runtimeId: string | null;
  runtimeOnline: boolean;
  primaryModel: string;
  value: string[];
  canEdit?: boolean;
  onChange: (next: string[]) => Promise<void> | void;
}

export function FallbackModelsEditor({
  runtimeId,
  runtimeOnline,
  primaryModel,
  value,
  canEdit = true,
  onChange,
}: FallbackModelsEditorProps) {
  const { t } = useT("agents");
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");

  const modelsQuery = useQuery(
    runtimeModelsOptions(runtimeOnline ? runtimeId : null),
  );
  const supported = modelsQuery.data?.supported ?? true;
  const models = useMemo(
    () => modelsQuery.data?.models ?? [],
    [modelsQuery.data],
  );

  const filtered = useMemo(() => {
    const s = search.trim().toLowerCase();
    const available = models.filter(
      (m) => m.id !== primaryModel && !value.includes(m.id),
    );
    if (!s) return available;
    return available.filter(
      (m) =>
        m.id.toLowerCase().includes(s) || m.label.toLowerCase().includes(s),
    );
  }, [models, primaryModel, value, search]);

  const trimmedSearch = search.trim();
  const exactMatch = models.some(
    (m) => m.id === trimmedSearch || m.label === trimmedSearch,
  );
  const canCreateCustom =
    trimmedSearch.length > 0 &&
    !exactMatch &&
    trimmedSearch !== primaryModel &&
    !value.includes(trimmedSearch);

  const canAddMore = value.length < MAX_FALLBACK_MODELS;

  const select = async (id: string) => {
    setOpen(false);
    setSearch("");
    if (!value.includes(id)) {
      await onChange([...value, id]);
    }
  };

  const remove = async (id: string) => {
    await onChange(value.filter((m) => m !== id));
  };

  const getModelLabel = (id: string) => {
    const model = models.find((m) => m.id === id);
    return model?.label || id;
  };

  if (!supported && !modelsQuery.isLoading && value.length === 0) {
    return (
      <span className="text-[11px] italic text-muted-foreground">
        {t(($) => $.pickers.model_managed_by_runtime)}
      </span>
    );
  }

  if (!canEdit) {
    if (value.length === 0) {
      return (
        <span className="text-[11px] italic text-muted-foreground">
          {t(($) => $.inspector.prop_fallback_models_empty)}
        </span>
      );
    }
    return (
      <div className="flex flex-wrap gap-1">
        {value.map((m) => (
          <span key={m} className={CHIP_CLASS} title={m}>
            {getModelLabel(m)}
          </span>
        ))}
      </div>
    );
  }

  return (
    <div className="flex flex-wrap items-center gap-1">
      {value.map((m) => (
        <span
          key={m}
          className={`${CHIP_CLASS} pr-0.5`}
          title={m}
        >
          {getModelLabel(m)}
          <button
            type="button"
            onClick={() => void remove(m)}
            className="ml-0.5 rounded-sm hover:bg-muted-foreground/20"
            aria-label={`Remove ${m}`}
          >
            <X className="h-2.5 w-2.5" />
          </button>
        </span>
      ))}

      {canAddMore && (
        <PropertyPicker
          open={open}
          onOpenChange={setOpen}
          width="w-auto min-w-[16rem] max-w-md"
          align="start"
          tooltip={t(($) => $.fallback_models.add)}
          triggerRender={
            <button
              type="button"
              className="inline-flex cursor-pointer items-center gap-0.5 rounded-md border border-dashed border-muted-foreground/30 px-1.5 py-0.5 text-[10px] font-medium text-muted-foreground/70 transition-colors hover:border-muted-foreground/60 hover:bg-accent/50 hover:text-muted-foreground"
              aria-label={t(($) => $.fallback_models.add)}
            />
          }
          trigger={
            <span className="inline-flex items-center gap-0.5 rounded-md border border-dashed border-muted-foreground/30 px-1.5 py-0.5 text-[10px] font-medium text-muted-foreground/70 transition-colors hover:border-muted-foreground/60 hover:bg-accent/50 hover:text-muted-foreground">
              <Plus className="h-2.5 w-2.5" />
              {t(($) => $.fallback_models.add)}
            </span>
          }
          header={
            <div className="p-1.5">
              <Input
                autoFocus
                placeholder={t(($) => $.fallback_models.add_dialog_search_placeholder)}
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="h-7 text-xs"
              />
            </div>
          }
        >
          {modelsQuery.isLoading && (
            <div className="flex items-center gap-2 p-3 text-xs text-muted-foreground">
              <Loader2 className="h-3 w-3 animate-spin" />
              {t(($) => $.pickers.model_discovering)}
            </div>
          )}

          {!modelsQuery.isLoading &&
            filtered.map((m) => (
              <PickerItem
                key={m.id}
                selected={false}
                onClick={() => void select(m.id)}
                tooltip={m.label !== m.id ? `${m.label} · ${m.id}` : m.id}
              >
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-1.5">
                    <span className="truncate font-medium">{m.label}</span>
                    {m.default && (
                      <span className="shrink-0 rounded bg-primary/10 px-1 text-[10px] font-medium text-primary">
                        {t(($) => $.pickers.model_default_badge)}
                      </span>
                    )}
                  </div>
                  {m.label !== m.id && (
                    <div className="truncate font-mono text-[10px] text-muted-foreground">
                      {m.id}
                    </div>
                  )}
                </div>
              </PickerItem>
            ))}

          {!modelsQuery.isLoading && filtered.length === 0 && !canCreateCustom && (
            <p className="px-3 py-3 text-center text-xs text-muted-foreground">
              {t(($) => $.fallback_models.add_dialog_empty)}
            </p>
          )}

          {canCreateCustom && (
            <PickerItem
              selected={false}
              onClick={() => void select(trimmedSearch)}
              tooltip={t(($) => $.pickers.model_custom_tooltip, { value: trimmedSearch })}
            >
              <Plus className="h-3.5 w-3.5 shrink-0 text-primary" />
              <span className="truncate text-primary">
                {t(($) => $.pickers.model_custom_use, { value: trimmedSearch })}
              </span>
            </PickerItem>
          )}
        </PropertyPicker>
      )}

      {!canAddMore && (
        <span className="text-[10px] text-muted-foreground">
          {t(($) => $.fallback_models.max_reached, { count: MAX_FALLBACK_MODELS })}
        </span>
      )}
    </div>
  );
}
